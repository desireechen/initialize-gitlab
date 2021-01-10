#!/bin/bash

# NOTE: re-run to re-allocate permission for each bucket (add,remove user from bucket); to delete bucket, a separate script read delete.csv

# Get Azure storage account key 
az login --service-principal --tenant $TENANT_ID  -u $APPLICATION_ID -p $AZCOPY_SPA_CLIENT_SECRET
AZURE_ACCOUNT_KEY=$(az storage account keys list  -n $AZURE_ACCOUNT_NAME | jq '.[0] | .value')
BACKUP_AZURE_ACCOUNT_KEY=$(az storage account keys list  -n $BACKUP_AZURE_ACCOUNT_NAME | jq '.[0] | .value')

# configure s3 
bash prepare_s3_config.sh



declare -A PROJECT_ARRAY

read -d '' ACL_CONTENT_EVERYONE_APPEND << EOF
    <Grant>
        <Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="Group">
            <URI>http://acs.amazonaws.com/groups/global/AllUsers</URI>
        </Grantee>
        <Permission>ACCESS</Permission>
    </Grant>
EOF

read -d '' ACL_CONTENT_APPEND << EOF
    <Grant>
        <Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="CanonicalUser">
            <ID>USER_ID</ID>
            <DisplayName>USER_ID</DisplayName>
        </Grantee>
        <Permission>ACCESS</Permission>
    </Grant>
EOF

read -d '' ACL_CONTENT_TEMPLATE << EOF
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <AccessControlPolicy xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
        <Owner>
            <ID>$S3_ACCESS_KEY_ID</ID>
            <DisplayName>$S3_ACCESS_KEY_ID</DisplayName>
        </Owner>
        <AccessControlList>
                <Grant>
                    <Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="CanonicalUser">
                        <ID>$S3_ACCESS_KEY_ID</ID>
                        <DisplayName>$S3_ACCESS_KEY_ID</DisplayName>
                    </Grantee>
                    <Permission>FULL_CONTROL</Permission>
                </Grant>
                USER_LIST
        </AccessControlList>
    </AccessControlPolicy>

EOF


read -r -d '' POLICY_CONTENT_APPEND << EOF
    {
      "Sid": "UDP-SID",
      "Action": [
         ACCESS
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::PROJECT_ID/*",
      "Principal": {
        "AWS": [
          "USER_ID"
        ]
      }
    }
EOF

read -r -d '' POLICY_CONTENT_EVERYONE_APPEND << EOF
    {
      "Sid": "UDP-SID",
      "Action": [
         ACCESS
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::PROJECT_ID/*",
      "Principal": "USER_ID",
    }
EOF


READ_WRITE=`echo "\"s3:GetObject\",\"s3:PutObject\""`
READ_ONLY=`echo "\"s3:GetObject\""`
WRITE_ONLY=`echo "\"s3:PutObject\""`

ts=$(date +"%F-%H%M")

# project_id in setup.csv cannot contain space or underscore
INPUT=setup.csv

# sort according to project_id and user_id
sort --field-separator=',' -r --key={1,2}  $INPUT > setup_process.csv


OLDIFS=$IFS
IFS=','
SKIP_COUNT=1
[ ! -f "setup_process.csv" ] && { echo "setup_process.csv file not found"; exit 99; }
while read project_id user_id access
do
    #skip header
    test $SKIP_COUNT -eq 1 && ((SKIP_COUNT=SKIP_COUNT+1)) && continue

    
    if [ -z "$project_id"  ]
    then
       echo "[SETUP] project_id variable is empty; skip processing"
       echo "[SETUP] -------Skipped ROW -------"
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

    key="${project_id}"
    if [[ -v PROJECT_ARRAY[$key] ]]   
    then
        PROJECT_ARRAY["${key}"]+=",${user_id}:${access}" 
       
    else
        PROJECT_ARRAY["${key}"]="${user_id}:${access}"
        
    fi

done < setup_process.csv
IFS=$OLDIFS






for i in ${!PROJECT_ARRAY[@]};
do 


    if [ $DRY_RUN_TEST_ONLY == "no" ]
    then
        echo "[SETUP] Checking whether Azure container exists"
        container_exists=$(az storage container exists --name $i --account-name $AZURE_ACCOUNT_NAME --account-key $AZURE_ACCOUNT_KEY | grep -Po '^ *"exists": [^/]*' | sed 's/^.*: //')
        if [ "$container_exists" == "false" ];
        then 
            echo "[SETUP] Create Azure container project=$i"
            az storage container create --name $i --account-name $AZURE_ACCOUNT_NAME --account-key $AZURE_ACCOUNT_KEY
        fi 

        echo "[SETUP] Checking S3 bucket $i"                                                                                                                                                                                                           
        BUCKET_EXISTS=true                                                                                                                                                                                                                            
        S3_CHECK=`AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY  aws s3 ls "s3://${i}" 2>&1`                                                                                                                                                 
                                                                                                                                                                                                
        if [ $? != 0 ]                                                                                                                                                                                                                                
        then                                                                                                                                                                                                                                          
        NO_BUCKET_CHECK=$(echo $S3_CHECK | grep -c 'NoSuchBucket')                                                                                                                                                                                     
        if [ $NO_BUCKET_CHECK = 1 ]; then                                                                                                                                                                                                              
            echo "[SETUP] Bucket does not exist"                                                                                                                                                                                                              
            BUCKET_EXISTS=false 
            echo "[SETUP] Create s3 bucket project=$i"
            AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY aws s3 mb s3://$i                                                                                                                                                                                             
        else                                                                                                                                                                                                                                        
            echo "[SETUP] Error checking S3 Bucket"                                                                                                                                                                                                           
            echo "[SETUP] $S3_CHECK"                                                                                                                                                                                                                          
            exit 1                                                                                                                                                                                                                                    
        fi 
        else                                                                                                                                                                                                                                         
        echo "[SETUP] Bucket exists, skip creation of bucket"
        fi  
    fi


    # append current user that run this script full access
    POLICY_EACH_USER_COPIED="${POLICY_CONTENT_APPEND//'USER_ID'/$S3_ACCESS_KEY_ID}" 
    POLICY_EACH_USER_COPIED="${POLICY_EACH_USER_COPIED//'PROJECT_ID'/$i}"
    POLICY_EACH_USER_COPIED="${POLICY_EACH_USER_COPIED//'ACCESS'/$READ_WRITE}"
    POLICY_EACH_USER_COPIED="${POLICY_EACH_USER_COPIED//'SID'/$ts}"
    
    POLICY_CONTENT_TEMPLATE_COPIED=`jq  --arg POLICY_CONTENT "$POLICY_EACH_USER_COPIED"  ".Statement[.Statement| length]  |= . + $POLICY_EACH_USER_COPIED " s3_template/policy_template.json` 
    echo "$POLICY_CONTENT_TEMPLATE_COPIED" > policy.json
    POLICY_CONTENT_TEMPLATE_COPIED=""

    ACL_CONCAT=""
    IFS=',' read -ra each_user <<< "${PROJECT_ARRAY[$i]}"

    for j in ${!each_user[@]};
    do 

        IFS=':' read -r user_id access <<< "${each_user[j]}"  


        # important need to trim last column of csv "access"
        access=`echo "$access" | tr -d '\r'`

        IFS=' ' read -ra each_access <<< "$access"

        for j in ${!each_access[@]};
        do
            
            # # create acl
            if echo x"$user_id" | grep '*' > /dev/null; then
                ACL_EACH_USER_COPIED="${ACL_CONTENT_EVERYONE_APPEND}"
            else 
                ACL_EACH_USER_COPIED="${ACL_CONTENT_APPEND//'USER_ID'/$user_id}"    
            fi
            ACL_EACH_USER_COPIED="${ACL_EACH_USER_COPIED//'ACCESS'/"${each_access[j]}"}"

            echo "[SETUP] each ACL $ACL_EACH_USER_COPIED"
            ACL_CONCAT="${ACL_CONCAT}${ACL_EACH_USER_COPIED}"

        done 
      
     

        # # create policy
        if echo x"$user_id" | grep '*' > /dev/null; then
            POLICY_EACH_USER_COPIED="${POLICY_CONTENT_EVERYONE_APPEND//'USER_ID'/$user_id}" 
        else
            POLICY_EACH_USER_COPIED="${POLICY_CONTENT_APPEND//'USER_ID'/$user_id}" 
        fi
        
        POLICY_EACH_USER_COPIED="${POLICY_EACH_USER_COPIED//'PROJECT_ID'/$i}"


      
           

        if [ "$access" == "READ" ] 
        then
             POLICY_EACH_USER_COPIED="${POLICY_EACH_USER_COPIED//'ACCESS'/$READ_ONLY}"
        elif [[ "$access" == "WRITE READ" || "$access" == "READ WRITE" || "$access" == "FULL_CONTROL" ]]
        then
            POLICY_EACH_USER_COPIED="${POLICY_EACH_USER_COPIED//'ACCESS'/$READ_WRITE}"
        elif [ "$access" == "WRITE" ] 
        then
             POLICY_EACH_USER_COPIED="${POLICY_EACH_USER_COPIED//'ACCESS'/$WRITE_ONLY}"
        else
            POLICY_EACH_USER_COPIED=""
            echo "[SETUP] invalid access detected"
        fi
    
        POLICY_EACH_USER_COPIED="${POLICY_EACH_USER_COPIED//'SID'/$ts}"      
        echo "[SETUP] each POLICY $POLICY_EACH_USER_COPIED"
        POLICY_CONTENT_TEMPLATE_COPIED=`jq  --arg POLICY_CONTENT "$POLICY_EACH_USER_COPIED"  ".Statement[.Statement| length]  |= . + $POLICY_EACH_USER_COPIED " policy.json`
        echo "$POLICY_CONTENT_TEMPLATE_COPIED" > policy.json
    done




    ACL_CONTENT_TEMPLATE_COPIED="${ACL_CONTENT_TEMPLATE//'USER_LIST'/$ACL_CONCAT}"
    echo "$ACL_CONTENT_TEMPLATE_COPIED"  > ./acl.xml
    
    if [ $DRY_RUN_TEST_ONLY == "no" ]
    then
        echo "[SETUP] executing ACL"
        perl s3curl.pl --id=personal --put acl.xml -- https://necs.nus.edu.sg/$i?acl
    fi
    rm ./acl.xml

    if [ $DRY_RUN_TEST_ONLY == "no" ]
    then
        echo "[SETUP] executing POLICY"
        perl s3curl.pl --id=personal --put policy.json -- https://necs.nus.edu.sg/$i?policy
    fi
    rm ./policy.json

    echo "[SETUP] value of DRY_RUN_TEST_ONLY=${DRY_RUN_TEST_ONLY}"    
    echo "[SETUP] ------- Done setting ACL & POLICY for project=$i -------" 

done
