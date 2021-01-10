#!/bin/bash

echo "Preparing ssh config file"

# prepare ssh config file
chmod go-r ~/.ssh/id*
sed "s#host_name#$GITLAB_HOST#g" -i ~/.ssh/config
sed "s#port_number#$GITLAB_PORT#g" -i ~/.ssh/config