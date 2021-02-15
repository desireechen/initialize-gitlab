### Overview of scripts

The scripts serve 2 main functions: 1) create Azure/S3 resources, sets ACL policies relating to S3, and 2) create GitLab groups and with versioning, if required.

Docker image:
- `requirements.txt`: `dvc[s3]` is added to this file. This contains the `boto3` library that DVC uses to communicate with AWS. 
- `Dockerfile`: Assembles an image that contains `Git` and `DVC`. Makes directories `.aws` and `.ssh` to contain the aws and ssh configurations respectively. The Docker container built from this image contains the various scripts. 

1. Create Azure/S3 resources, sets ACL policies relating to S3.

Both `create_gitlab_group.sh` and `create_gitlab_group_dvc.sh` call GitLab API and create group(s) in GitLab. Not able to create another group with a similar name. Groups can be created using a Personal Access Token (obtained from GitLab user account) placed under the Bearer Token Authorization argument in the curl command. 

- `config_files/awsconfig` and `prepare_s3_config.sh`: Contain the aws configuration. 
- `setup.csv`: Contains group names (e.g. b7abc, b7def), users and access rights.
- `azure_ecs_dvc.sh`: Reads from `setup.csv`. Creates Azure containers and S3 buckets. Also, sets ACL and policies relating to S3.
- `delete.csv`: Contains group names to be deleted. 
- `automation_delete.sh`: Deletes Azure/S3 resources that are no longer required. 

2. Create GitLab groups and with versioning (`project_data` repository), if required.

- `config_files/sshconfig` and `prepare_ssh_config.sh`: Contain the ssh configuration. 
- `create_gitlab_group_dvc.sh`: Creates group for projects that use DVC. The DVC remote storage is the `.dvc_cache` folder in the S3 bucket.

### Prepare your workspace

1. Ensure that you have Docker installed.
2. Git clone this repository.
2. `cd initialize-gitlab`
3. Make `.env` file. See next section for sample `.env` file.
4. Build docker image: `docker build -t genesis .`
5. Go to `inputs` folder. Amend `setup.csv` to have the various projects, users and access rights for S3 bucket. Amend `gitlab.csv` to have the various projects, users and access levels for GitLab groups. Amend `delete.csv` to have the projects to be deleted. _Project names cannot contain spaces or underscores._ 

### Sample `.env` file

APPLICATION_ID=b2-0dcyvba-c04fc-ei98cb-0

TENANT_ID=74f371b98nbosn-0dcyvb-eivihgnds]

AZCOPY_SPA_CLIENT_SECRET=9h8ig371b98nbou2ZR6HkrFBTHvH

AZURE_ACCOUNT_NAME=teststorageaccount

S3_ACCESS_KEY_ID=the_user
S3_SECRET_ACCESS_KEY=RHkrFBTfc-eiIP3ZZPPwVrlDPGl1Nt
S3CURL_ENDPOINT=ecs.mit.execute.org

GITLAB_HOST=gitlab.int.execute.org
GITLAB_PORT=2929
SSH_FOR_GITLAB_PUBLIC=ssh-ed25519 AABBBCCCCCDDPOOOOOOORJGBJPt2NL data_architect@execute.org
SSH_FOR_GITLAB_PRIVATE=-----BEGIN OPENSSH PRIVATE KEY-----\ccytrrpbnuydbnb3Blbbm9uZQAAAAgtZW\T9ug1Nt0elblt7z7djSwAKx7f\2gF\n-----END OPENSSH PRIVATE KEY-----
BEARER_TOKEN=ig371b98nbou2ZR6Hk

### How to run scripts?

1. To create Azure containers and S3 buckets

```
docker run \
  --env DRY_RUN_TEST_ONLY=no \
  --env-file .env \
  -v $(pwd)/inputs/setup.csv:/home/appuser/setup.csv \
  genesis:latest /bin/bash azure_ecs_dvc.sh
```

2. To create GitLab groups with versioning

```
docker run \
  --env DRY_RUN_TEST_ONLY=no \
  --env-file .env \
  -v $(pwd)/inputs/gitlab.csv:/home/appuser/gitlab.csv \
  genesis:latest /bin/bash create_gitlab_group_dvc.sh
```

3. To delete Azure/S3 resources

```
docker run \
  --env DRY_RUN_TEST_ONLY=no \
  --env-file .env \
  -v $(pwd)/inputs/delete.csv:/home/appuser/delete.csv \
  genesis:latest /bin/bash automation_delete.sh
```

In a dry run whereby `DRY_RUN_TEST_ONLY=yes`, no Azure containers or S3 buckets will be created.
