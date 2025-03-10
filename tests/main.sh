#!/bin/bash

assert ()
{
	E_PARAM_ERR=98
	E_ASSERT_FAILED=99

	if [ -z "$3" ]; then
		return $E_PARAM_ERR
	fi

	lineno=$3
	if ! eval "$2"; then
		echo "Assertion ($1) failed:  \"$2\""
		echo "File \"$0\", line $lineno"
		echo "---------------- TEST[$SHELL_CMD_FLAGS]: $1 ❌ ----------------" | \
			tr -d '\t'
		exit $E_ASSERT_FAILED
	else
		echo "---------------- TEST[$SHELL_CMD_FLAGS]: $1 ✅ ----------------" | \
			tr -d '\t'
	fi
}
validate () {
	assert "debugger available" "[ $($SHELL_CMD 'eval "$(cat)"' <<-END
		pip list --format=freeze 2>/dev/null | \
			grep ipykernel | \
			grep -qv "ipykernel==5\." && \
		echo done
	END
	) == 'done' ]" $LINENO
	SHELL_CMD_FLAGS="-e JUPYTER_LAB_DEFAULT_URL=/home/anaconda/README.md"
	SHELL_CMD=$(eval "echo \"$SHELL_CMD_TEMPLATE\"")
	assert "check landing page" "[ $($SHELL_CMD 'eval "$(cat)"' <<-END
		jupyter lab > /tmp/logs 2>&1 & \
		sleep 5 && \
		cat /tmp/logs | \
			grep -q "http://127.0.0.1:8888/lab/tree/anaconda/README.md" && \
		echo done
	END
	) == 'done' ]" $LINENO
	assert "check default password" "[ $($SHELL_CMD 'eval "$(cat)"' <<-END
		jupyter lab > /tmp/logs 2>&1 & \
		sleep 5 && \
		python <<EOF
		import requests
		s = requests.Session()
		url = 'http://127.0.0.1:8888/login?next=%2Flab'
		resp = s.get(url)
		xsrf_cookie = resp.cookies["_xsrf"]

		params = {'_xsrf': xsrf_cookie, 'password': 'datajoint'}
		resp = s.post(url, data=params)
		print(resp.status_code)
		EOF
	END
	) == 200 ]" $LINENO
	SHELL_CMD_FLAGS="-e JUPYTER_SERVER_PASSWORD=test"
	SHELL_CMD=$(eval "echo \"$SHELL_CMD_TEMPLATE\"")
	assert "check setting password by env var" "[ $($SHELL_CMD 'eval "$(cat)"' <<-END
		ipython -c "import os; print(os.getenv('JUPYTER_SERVER_PASSWORD'))"
	END
	) == 'test' ]" $LINENO
	assert "check jupyter_server_config.py permissions" "[ $($SHELL_CMD 'eval "$(cat)"' <<-END
		ls -la /home/anaconda/.jupyter/jupyter_server_config.py | cut -d ' ' -f1 | tr -d '\n'
	END
	) == '-rwxrwxr-x' ]" $LINENO
	assert "check jupyter_lab_config.py permissions" "[ $($SHELL_CMD 'eval "$(cat)"' <<-END
		ls -la /home/anaconda/.jupyter/jupyter_lab_config.py | cut -d ' ' -f1 | tr -d '\n'
	END
	) == '-rwxrwxr-x' ]" $LINENO
}
# set image context
REF=$(eval \
	"echo $(cat dist/${DISTRO}/docker-compose.yaml | grep 'image:' | awk '{print $2}')")
TAG=$(echo $REF | awk -F':' '{print $2}')
IMAGE=$(echo $REF | awk -F':' '{print $1}')
SHELL_CMD_TEMPLATE="docker run --rm -i \$SHELL_CMD_FLAGS $REF \
	$([ ${DISTRO} == 'debian' ] && echo bash || echo sh) -c"
# Get the compressed size of the last build from docker hub
LAST_BUILD_SIZE=$(curl -s https://hub.docker.com/v2/repositories/$IMAGE/tags \
	| jq -r '.results[] | select(.name=="py'"$PY_VER"'-'"$DISTRO"'") | .images[0].size')
SIZE_INCRESE_FACTOR=1.5
SIZE_LIMIT=$(echo "scale=4; $LAST_BUILD_SIZE * $SIZE_INCRESE_FACTOR" | bc)
# Verify size minimal
echo Compressing image for size verification...
docker save $REF | gzip > /tmp/$TAG.tar.gz
SIZE=$(ls -al /tmp | grep $TAG.tar.gz | awk '{ print $5 }')
echo -e \
	Size comparison:\\n\
	Current size: $(numfmt --to iec --format "%8.4f" $SIZE)\\n\
	Last build size:  $(numfmt --to iec --format "%8.4f" $LAST_BUILD_SIZE)\\n\
	Size factor: $SIZE_INCRESE_FACTOR\\n\
	Size limit: $(numfmt --to iec --format "%8.4f" $SIZE_LIMIT)
assert "minimal footprint" "(( $(echo "$SIZE <= $SIZE_LIMIT" | bc -l) ))" $LINENO
rm /tmp/$TAG.tar.gz
run tests
SHELL_CMD=$(eval "echo \"$SHELL_CMD_TEMPLATE\"")
validate
