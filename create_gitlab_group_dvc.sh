#!/bin/bash

# create ssh key 
mkdir -p ~/.ssh
echo "${SSH_FOR_GITLAB_PRIVATE//'\n'/$'\n'}"  > ~/.ssh/id_ed25519
echo $SSH_FOR_GITLAB_PUBLIC > ~/.ssh/id_ed25519.pub

# configure ssh
bash prepare_ssh_config.sh

# project_id in gitlab.csv cannot contain space or underscore
INPUT=gitlab.csv

# sort according to project_id and user_id
sort --field-separator=',' -r --key={1,2}  $INPUT > gitlab_process.csv

OLDIFS=$IFS
IFS=','
SKIP_COUNT=1
[ ! -f "gitlab_process.csv" ] && { echo "gitlab_process.csv file not found"; exit 99; }
while read project_id user_id access
do
    # skip header
    test $SKIP_COUNT -eq 1 && ((SKIP_COUNT=SKIP_COUNT+1)) && continue

    if [ -z "$project_id"  ]
    then
       echo "[INFO] project_id variable is empty; skip processing"
       echo "[INFO] -------Skipped ROW -------"
       continue
    fi
    if [ -z "$user_id"  ]
    then
       echo "[SETUP] user_id variable is empty; skip processing"
       echo "[SETUP] -------Skipped ROW -------"
       continue
    fi
    if [ -z "$access"  ]
    then
       echo "[SETUP] access variable is empty; skip processing"
       echo "[SETUP] -------Skipped ROW -------"
       continue
    fi

   echo "[SETUP] Start to extract $project_id $user_id $access"

   curl --location --request POST "https://$GITLAB_HOST/api/v4/groups" \
   --header "Authorization: Bearer $BEARER_TOKEN" \
   --header 'Content-Type: application/x-www-form-urlencoded' \
   --data-urlencode "name=$project_id" \
   --data-urlencode "path=$project_id"

   curl --request POST --header "Authorization: Bearer $BEARER_TOKEN" \
   --data "email=$user_id&access_level=$access" "https://$GITLAB_HOST/api/v4/groups/$project_id/invitations" 

   LIST_PROJECTS=$(curl --request GET --header "Authorization: Bearer $BEARER_TOKEN"     "https://$GITLAB_HOST/api/v4/groups/$project_id/projects")
   PROJECT_EXISTS=$(echo $LIST_PROJECTS | grep -c "$project_id / project_data")

   if [ $PROJECT_EXISTS = 0 ]; then
      export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
      git init
      dvc init -f
      git config user.name "Data Architect"
      git config user.email "data_architect@execute.org"
      dvc remote add -d ecs "s3://$project_id/.dvc_cache"
      dvc remote modify ecs endpointurl "https://$S3CURL_ENDPOINT"
      dvc remote modify ecs --local access_key_id $S3_ACCESS_KEY_ID
      dvc remote modify ecs --local secret_access_key $S3_SECRET_ACCESS_KEY
      mkdir -p data/{raw,interim,processed}
      echo '!'"**/*.dvc" > data/raw/.gitignore
      echo '!'"**/*.dvc" > data/interim/.gitignore
      echo '!'"**/*.dvc" > data/processed/.gitignore
      git add data/raw data/interim data/processed data/raw/.gitignore data/interim/.gitignore data/processed/.gitignore
      git add .dvc/.gitignore .dvc/config .dvcignore
      git add .dvc/plots/confusion.json .dvc/plots/confusion_normalized.json .dvc/plots/default.json .dvc/plots/scatter.json .dvc/plots/smooth.json
      git commit -m "Initial commit"
      git push --set-upstream git@$GITLAB_HOST:$project_id/project_data.git master
   else
      echo "Project exists, hence no need to initialise Git and DVC again."
   fi

done < gitlab_process.csv
IFS=$OLDIFS