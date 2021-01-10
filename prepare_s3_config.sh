#!/bin/bash

echo "Preparing s3 config"
# prepare aws cli
sed "s#server_name#$S3CURL_ENDPOINT#g" -i ~/.aws/config

# prepare s3curl
chmod 600 ~/.s3curl
sed "s#AWS_ACCESS_KEY_ID#$S3_ACCESS_KEY_ID#g" -i ~/.s3curl
sed "s#AWS_SECRET_ACCESS_KEY#$S3_SECRET_ACCESS_KEY#g" -i ~/.s3curl
