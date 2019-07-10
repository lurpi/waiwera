FROM debian:stretch-slim

ARG git_user
ARG git_pwd
ARG base_dir

RUN apt-get update && \
    apt-get install -y \
        locales && \
    rm -rf /var/lib/apt/lists/* && \
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 && \
    apt-get autoremove -y && apt-get autoclean -y && apt-get clean -y && \
    rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/doc/*  \
        /root/.pip/cache/*
ENV LANG en_US.utf8


ADD ansible /ansible

RUN apt update && \
    apt install -y --no-install-recommends  \
        python3-minimal \
        python3-pip \
        python3-setuptools \
        python3-wheel && \
    pip3 install ansible &&\
    usr/local/bin/ansible-playbook \
        --connection=local \
        /ansible/local.yml \
        -v \
        -e "waiwera_user=${git_user}" \
        -e "waiwera_pwd=${git_pwd}" \
        -e "base_dir=${base_dir}" \
        --tags=all,docker \
        --skip-tags=local,zofu,fson && \
    pip3 uninstall ansible -y && \
    apt-get autoremove -y && \
    apt-get autoclean -y && \
    apt-get clean -y && \
    rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/doc/*  \
        /root/.pip/cache/*

RUN rm -r /ansible

USER 1000:1000

WORKDIR ${base_dir}/waiwera
