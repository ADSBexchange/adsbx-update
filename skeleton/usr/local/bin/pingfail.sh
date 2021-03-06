#!/bin/bash

trap "exit" INT TERM
trap "kill 0" EXIT

TEST1="google.com"
TEST2="akamai.com"
FAIL="no"

while sleep 1800
do
	if ping $TEST1 -c1 -w5 >/dev/null || ping $TEST2 -c1 -w5 >/dev/null
	then
		FAIL="no"
	elif [[ "$FAIL" == yes ]]
	then
		if ! ping $TEST1 -c5 -w20 >/dev/null && ! ping $TEST2 -c5 -w20 >/dev/null
		then
            echo "$(date): Restarting dhcpcd, could reach neither $TEST1 nor $TEST2" | tee -a /var/log/pingfail
            systemctl restart dhcpcd.service
		fi
		FAIL="no"
	else
		FAIL="yes"
	fi
done

