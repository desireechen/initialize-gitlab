FROM debian:stretch-slim

ENV TZ Asia/Singapore

RUN apt-get update -qq && \
    apt-get install -qqy --no-install-recommends git curl wget unzip ca-certificates jq openssh-server bc cpanminus libdigest-hmac-perl

RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

ENV RELEASE_STAMP=20200818
ENV RELEASE_VERSION=10.6.0

RUN set -ex \
    && curl -L -o azcopy.tar.gz https://azcopyvnext.azureedge.net/release${RELEASE_STAMP}/azcopy_linux_amd64_${RELEASE_VERSION}.tar.gz \
    && tar -xzf azcopy.tar.gz && rm -f azcopy.tar.gz \
    && cp ./azcopy_linux_amd64_*/azcopy /usr/local/bin/. \
    && chmod +x /usr/local/bin/azcopy \
    && rm -rf azcopy_linux_amd64_*

RUN useradd  --create-home appuser
USER appuser
WORKDIR /home/appuser

RUN mkdir -p .aws
RUN mkdir -p .ssh

COPY --chown=appuser:appuser ./requirements.txt .
# s3curl.pl, .s3curl, awsconfig, sshconfig do not contain user credentials
COPY --chown=appuser:appuser s3curl.pl .
COPY --chown=appuser:appuser config_files/.s3curl .
COPY --chown=appuser:appuser config_files/awsconfig /home/appuser/.aws/config
RUN chmod go-r ~/.aws/*
COPY --chown=appuser:appuser config_files/sshconfig /home/appuser/.ssh/config
RUN chmod go-r ~/.ssh/*
COPY --chown=appuser:appuser prepare_s3_config.sh .
COPY --chown=appuser:appuser s3_template ./s3_template
COPY --chown=appuser:appuser azure_ecs_dvc.sh .
COPY --chown=appuser:appuser prepare_ssh_config.sh .
COPY --chown=appuser:appuser create_gitlab_group_dvc.sh .
COPY --chown=appuser:appuser automation_delete.sh .

ENV CONDA_DIR /home/appuser/.conda

RUN wget -nv -O miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-py37_4.8.2-Linux-x86_64.sh \
 && bash miniconda.sh -b -p ${CONDA_DIR} \
 && . ${CONDA_DIR}/etc/profile.d/conda.sh \
 && rm -rf miniconda.sh
ENV PATH ${CONDA_DIR}/bin:${PATH}

# install s3
# version 2 does not work with awscli-plugin-endpoint, https://github.com/wbingli/awscli-plugin-endpoint
# RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.0.34.zip" -o "awscliv2.zip" && unzip awscliv2.zip &&  ./aws/install
# use version 1
RUN curl "https://s3.amazonaws.com/aws-cli/awscli-bundle-1.18.104.zip" -o "awscli-bundle.zip" && unzip awscli-bundle.zip && ./awscli-bundle/install -b ~/.bin/aws 
ENV PATH ${PATH}:~/.bin  

RUN pip install -r requirements.txt