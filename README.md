### Overview of scripts

The scripts serve 2 main functions: 1) create Azure/S3 resources, sets ACL policies relating to S3, and 2) create GitLab groups and with versioning, if required.

Docker image:
- `requirements.txt`: `dvc[s3]` is added to this file. This contains the `boto3` library that DVC uses to communicate with AWS. 
- `Dockerfile`: Assembles an image that contains `Git` and `DVC`. Makes directories `.aws` and `.ssh` to contain the aws and ssh configurations respectively. The Docker container built from this image contains the various scripts. 

1. Create Azure/S3 resources, sets ACL policies relating to S3.

Both `create_gitlab_group.sh` and `create_gitlab_group_dvc.sh` call GitLab API and create group(s) in GitLab. Not able to create another group with a similar name. Groups can be created using a Personal Access Token (obtained from above GitLab user account) placed under the Bearer Token Authorization argument in the curl command. 

- `config_files/awsconfig` and `prepare_s3_config.sh`: Contain the aws configuration. 
- `setup.csv`: Contains group names (e.g. SGH, IRAS), users and access rights.
- `azure_ecs_dvc.sh`: Reads from `setup.csv`. Creates Azure containers and S3 buckets. Also, sets ACL and policies relating to S3.
- `delete.csv`: Contains group names to be deleted. 
- `automation_delete.sh`: Deletes Azure/S3 resources that are no longer required. 

2. Create GitLab groups and with versioning (`project_data` repository), if required.

- `config_files/sshconfig` and `prepare_ssh_config.sh`: Contain the ssh configuration. 
- `create_gitlab_group_dvc.sh`: Creates group for projects that use DVC. The DVC remote storage is the `.dvc_cache` folder in the S3 bucket.

### Prepare your workspace

1. `git clone https://github.com/desireechen/initialize-gitlab.git`
2. `cd initialize-gitlab`
3. Make `.env` file.
4. Build docker image: `docker build -t genesis .`
5. Go to `inputs` folder. Amend `setup.csv` to have the various projects, users and access rights. Amend `gitlab.csv` to have the projects that require GitLab groups. Amend `delete.csv` to have the projects to be deleted. _Project names cannot contain spaces or underscores._ 

### How to run scripts?

1. To create Azure containers and S3 buckets

```
docker run \
  --env DRY_RUN_TEST_ONLY=no \
  --env-file .env \
  -v /home/desiree/setup-scripts/inputs/setup.csv:/home/appuser/setup.csv \
  genesis:latest /bin/bash azure_ecs_dvc.sh
```

2. To create GitLab groups with versioning

```
docker run \
  --env DRY_RUN_TEST_ONLY=no \
  --env-file .env \
  -v /home/desiree/setup-scripts/inputs/gitlab.csv:/home/appuser/gitlab.csv \
  genesis:latest /bin/bash create_gitlab_group_dvc.sh
```

3. To delete Azure/S3 resources

```
docker run \
  --env DRY_RUN_TEST_ONLY=no \
  --env-file .env \
  -v /home/desiree/setup-scripts/inputs/delete.csv:/home/appuser/delete.csv \
  genesis:latest /bin/bash automation_delete.sh
```

In a dry run whereby `DRY_RUN_TEST_ONLY=yes`, no Azure containers or S3 buckets will be created.