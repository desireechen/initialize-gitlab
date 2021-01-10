#!/bin/bash
bash prepare_s3_config.sh

# Get Azure storage account key 
az login --service-principal --tenant $TENANT_ID  -u $APPLICATION_ID -p $AZCOPY_SPA_CLIENT_SECRET
AZURE_ACCOUNT_KEY=$(az storage account keys list  -n $AZURE_ACCOUNT_NAME | jq '.[0] | .value')

INPUT=delete.csv
cp $INPUT delete_process.csv
# workaround: otherwise does not read the last line
echo "" >> delete_process.csv

OLDIFS=$IFS
IFS=''
SKIP_COUNT=1
[ ! -f "delete_process.csv" ] && { echo "delete_process.csv file not found"; exit 99; }
while read project_id
do
    #skip header
    test $SKIP_COUNT -eq 1 && ((SKIP_COUNT=SKIP_COUNT+1)) && continue

    # important need to trim last column 
    project_id=`echo "$project_id" | tr -d '\r'`

    if [ -z "$project_id"  ]
    then
       echo "[INFO] project_id variable is empty; skip processing"
       echo "[INFO] -------Skipped ROW -------"
       continue
    fi

    # important need to trim last column of csv "access"
    project_id=`echo "$project_id" | tr -d '\r'`

    echo "[INFO] Delete s3 bucket https://$S3CURL_ENDPOINT/$project_id"
    AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY aws s3 rb s3://$project_id --force  

    echo "[INFO] Delete azure container $project_id"
    az storage container delete --name $project_id --account-name $AZURE_ACCOUNT_NAME --account-key $AZURE_ACCOUNT_KEY
    
done < delete_process.csv
IFS=$OLDIFS

