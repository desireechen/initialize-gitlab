#!/bin/bash

# create ssh key 
mkdir -p ~/.ssh
echo "${SSH_FOR_GITLAB_PRIVATE//'\n'/$'\n'}"  > ~/.ssh/id_ed25519
echo $SSH_FOR_GITLAB_PUBLIC > ~/.ssh/id_ed25519.pub

# configure ssh
bash prepare_ssh_config.sh

INPUT=gitlab.csv
cp $INPUT gitlab_process.csv
# workaround: otherwise does not read the last line
echo "" >> gitlab_process.csv

OLDIFS=$IFS
IFS=''
SKIP_COUNT=1
[ ! -f "gitlab_process.csv" ] && { echo "gitlab_process.csv file not found"; exit 99; }
while read project_id
do
    # skip header
    test $SKIP_COUNT -eq 1 && ((SKIP_COUNT=SKIP_COUNT+1)) && continue

    # important need to trim last column 
    project_id=`echo "$project_id" | tr -d '\r'`

    if [ -z "$project_id"  ]
    then
       echo "[INFO] project_id variable is empty; skip processing"
       echo "[INFO] -------Skipped ROW -------"
       continue
    fi

    curl --location --request POST "https://$GITLAB_HOST/api/v4/groups" \
    --header "Authorization: Bearer $BEARER_TOKEN" \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "name=$project_id" \
    --data-urlencode "path=$project_id"

    export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    git init
    dvc init -f
    git config user.name "Data Architect"
    git config user.email "data_architect@execute.org"
    dvc remote add -d ecs "s3://$project_id/.dvc_cache"
    dvc remote modify ecs endpointurl "https://$S3CURL_ENDPOINT"
    dvc remote modify ecs access_key_id $S3_ACCESS_KEY_ID
    dvc remote modify ecs secret_access_key $S3_SECRET_ACCESS_KEY
    mkdir -p data/{raw,interim,processed}
    cd data/raw
    touch .gitkeep
    cd ..
    cd interim
    touch .gitkeep
    cd ..
    cd processed
    touch .gitkeep
    cd ..
    cd ..
    git add data/raw data/interim data/processed
    git add .dvc/.gitignore .dvc/config .dvcignore
    git add .dvc/plots/confusion.json .dvc/plots/confusion_normalized.json .dvc/plots/default.json .dvc/plots/scatter.json .dvc/plots/smooth.json
    git commit -m "Initial commit"
    git push --set-upstream git@$GITLAB_HOST:$project_id/project_data.git master
    
done < gitlab_process.csv
IFS=$OLDIFS