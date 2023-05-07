#!/bin/bash

# Copyright 2019 xiak.com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This file creates release artifacts (tar files, container images) that are
# ready to distribute to install or distribute to end users.

if [ "$#" -lt 2 ] || [ "${1}" == "--help" ]; then
  cat <<EOF

Description:
Install docker binaries (version must be gt 18.06)

Usage: $(basename "$0") <docker version> <strategy>
  <docker version>   docker version
  <strategy>         keep or new

Examples:
  # set strategy=new means, it will uninstall docker and then re-install it
  $(basename "$0") 18.09.7 new
  # set strategy=keep means if docker 18.09.7 was installed on server, it will skip installation, else install docker 18.09.7
  $(basename "$0") 18.09.7 keep

EOF
  exit 1
fi

source lib/fmt.sh
source lib/assert.sh
source lib/pkg.sh
source lib/ssh.sh
source lib/service.sh

DOCKER_VERSION=${1}
STRATEGY=${2}

# 参数配置
DOCKER_ARCH=`arch`
DOCKER_SERVICE_NAME=docker
DOCKER_BIN_DIR=/usr/local/bin
DOCKER_WORK_DIR=/etc/docker
DOCKER_PKG_DIR=${DOCKER_WORK_DIR}/install
# version <= 18.06 docker-${1}-ce.tgz
# version >= 18.09 docker-${1}.tgz
DOCKER_PKG_NAME=docker-${1}.tgz
DOCKER_SERVICE_DIR=/usr/lib/systemd/system
DOCKER_SERVICE_FILE=${DOCKER_SERVICE_NAME}.service
DOCKER_ENV_DIR=${DOCKER_WORK_DIR}/config
DOCKER_ENV_FILE=${DOCKER_SERVICE_NAME}.env
DOCKER_PKG_URL="https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/${DOCKER_PKG_NAME}"

# 直接拷贝解压后文件夹内所有文件
# version 18.06
# DOCKER_TOOLS=("docker" "dockerd" "docker-containerd" "docker-containerd-ctr" "docker-containerd-shim" "docker-init" "docker-proxy" "docker-runc")
# version 18.09
DOCKER_TOOLS=("docker" "dockerd" "containerd" "ctr" "containerd-shim" "docker-init" "docker-proxy" "runc" )

function docker::start::service() {
    # centos7 下默认为 /usr/lib/systemd/system
    local service_dir=${1}
    # docker.service
    local service_file=${2}
    # /usr/local/bin
    local bin_dir=${3}
    local env_dir=${4}
    local env_file=${5}

    local env_file_path="${env_dir}/${env_file}"
    local service_file_path="${service_dir}/${service_file}"

    fmt::info "Create docker environment config"
    mkdir -p ${env_dir}
    # env put here
    cat > ${env_file_path} <<EOF
EOF
    fmt::info "Create docker service file"
    # flannel 需要修改一下配置
    # ExecStart=/usr/local/bin/dockerd $DOCKER_NETWORK_OPTIONS
    cat > ${service_file_path} <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
EnvironmentFile=-${env_file_path}
ExecStart=${bin_dir}/dockerd
EOF
    # "EOF" 让 $MAINPID 保持原样
    cat >> ${service_file_path} <<"EOF"
ExecReload=/bin/kill -s HUP $MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
    fmt::info "Start docker service"
    systemctl daemon-reload
    systemctl enable docker
    systemctl restart docker
    service::local::wait_until_active docker 10
}

function docker::install::strategy() {
    # keep or reinstall
    local strategy=${1}
    # docker 18.09.7
    local version=${2}
    # docker arch
    local arch=${3}
    # 下载目录
    local pkg_dir=${4}
    # docker 二进制包名
    local pkg_name=${5}
    # bin 目录
    local bin_dir=${6}
    # docker.service 目录
    local svc_dir=${7}
    # docker.service
    local svc_file=${8}
    # docker.env 目录
    local env_dir=${9}
    # docker.env
    local env_file=${10}
    # docker download url
    local docker_url=${11}
    shift 11
    # docker binaries
    local bin_files=$@

    local env_file_path="${env_dir}/${env_file}"
    local svc_file_path="${svc_dir}/${svc_file}"

    fmt::info "The docker installation strategy is: ${strategy}"

    # 如果没有安装 docker
    fmt::process "Check docker binary"
    if ! (hash docker) >/dev/null 2>&1; then
        fmt::ok "Not installed"
        pkg::download ${docker_url} ${version} ${pkg_name} ${pkg_dir} docker ${bin_dir} true "${bin_files[@]}"
        docker::start::service ${svc_dir} ${svc_file} ${bin_dir} ${env_dir} ${env_file}
    else
        fmt::ok "Already installed"
        docker -v
        if [ "${2}" == "keep" ]; then
            service::local::wait_until_active docker 10
        else
            fmt::info "Strategy (${strategy}) will re-install docker binary and service"
            systemctl stop docker
            systemctl disable docker
            # 卸载通过 yum 安装的 docker
            yum remove -y containerd.io.${arch} \
                          docker-ce.${arch} \
                          docker-ce-cli.${arch} \
                          docker \
                          docker-client \
                          docker-client-latest \
                          docker-common \
                          docker-latest \
                          docker-latest-logrotate \
                          docker-logrotate \
                          docker-engine
            # 卸载 bin_dir 下的 binary
            for binary in ${bin_files[@]}; do
                rm -f "${bin_dir}/${binary}"
            done
            rm -f "${bin_dir}/docker*"
            # 卸载环境变量文件
            rm -f ${env_file_path}
            # 卸载 service 文件
            rm -f ${svc_file_path}

            # 重新安装 docker
            pkg::download ${docker_url} ${version} ${pkg_name} ${pkg_dir} docker ${bin_dir} true "${bin_files[@]}"
            docker::start::service ${svc_dir} ${svc_file} ${bin_dir} ${env_dir} ${env_file}
        fi
    fi
}

docker::install::strategy \
  ${STRATEGY} \
  ${DOCKER_VERSION} \
  ${DOCKER_ARCH} \
  ${DOCKER_PKG_DIR} \
  ${DOCKER_PKG_NAME} \
  ${DOCKER_BIN_DIR}  \
  ${DOCKER_SERVICE_DIR} \
  ${DOCKER_SERVICE_FILE} \
  ${DOCKER_ENV_DIR} \
  ${DOCKER_ENV_FILE} \
  ${DOCKER_PKG_URL} \
  "${DOCKER_TOOLS[@]}"

