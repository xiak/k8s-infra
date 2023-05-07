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


if [ "$#" -lt 16 ] || [ "${1}" == "--help" ]; then
  cat <<EOF

Description:
Create or join kubernetes cluster
NOTE: Container runtime only support docker
NOTE: Every node should have the same user password
NOTE: You shold re-create kubeadm token when there are not availid tokens or tokens were expired
      cmd: kubeadm token create
NOTE: If the error occurred, please check if the time on every nodes are the same
      ERROR: Unable to connect to the server: x509: certificate has expired or is not yet valid
NOTE: The default POD CIDR is 172.172.0.0/16 and SERVICE CIDR is 10.10.0.0/16

Usage: $(basename "$0") <host> <user> <password> <k8s version> <docker version> <SLB API addr> <SLB etcd addr> <etcd node addr> <k8s master node> <Action> <Role> <Proxy> <cgroup driver> <docker registry> <etcd cert dir> <ntp servers> ...
  <host>             host name or ip address of node
  <user>             user name of node
  <password>         password of node
  <k8s version>      kubernetes version
  <docker version>   docker version
  <SLB API addr>     kube-apiserver VIP:port, e.g 10.10.0.1:8443
  <SLB etcd addr>    etcd cluster VIP:port, e.g 10.10.0.1:2379
  <etcd node addr>   the first node address of etcd cluster
  <k8s master node>  only used for join cluster operation
  <Action>           new | join - create a new cluster of join a existed cluster
  <Role>             master | worker - A master node or worker node
  <Proxy>            ipvs | iptables
  <cgroup driver>    systemd | cgroupfs
  <docker registry>  docker registry
  <etcd cert dir>    etcd cert dir on etcd server
  <ntp server 1>     ntp server
  <ntp server 2>     ntp server
  ...

Precondition:
  # 1. Design the kubernetes strategy in file /etc/hosts and then copy it to all hosts which were defined in /etc/hosts
  install-etc-hosts.sh root password
  # 2. Install soft loadbalancer cluster for kubernetes apiserver or etcd cluster
  install-slb.sh root password 10.10.10.100 ens160 "10.10.10.6 10.10.10.7 10.10.10.8" "10.10.10.3 10.10.10.4 10.10.10.5" 10.10.10.9 10.10.10.10 10.10.10.11
  # 3. Install etcd cluster
  install-etcd.sh root password 3.4.3 etcd-cluster-vip.com 10.10.10.100 /etc/etcd 10.10.10.3 10.10.10.4 10.10.10.5

Dependency:
  This script has invoked 2 scripts, please make sure they are existing at same path of this script:
  - bootstrap.sh
  - install-docker.sh

Examples:
  # For this command, we will install a kubernetes api server
  # IP: 10.10.10.6
  # Role: master
  # Kubernetes Version: 1.16.2
  # Docker Version: 18.09.7
  # Docker Registry: hub.docker.com
  # Kubernetes API Server VIP: 10.10.10.100:8443
  # ETCD Cluster VIP: 10.10.10.100:2379
  # ETCD Cert Path: /etc/etcd/pki on etcd-first-node.com
  # Network Proxy: IPVS
  # Cgroup Driver: systemd
  # NTP Servers: 10.10.10.9, 10.10.10.10, 10.10.10.11
  $(basename "$0") 10.10.10.6 root password 1.16.2 18.09.7 10.10.10.100:8443 10.10.10.100:2379 etcd-first-node.com "" new master ipvs systemd hub.docker.com /etc/etcd/pki 10.10.10.9 10.10.10.10 10.10.10.11

  # Join a node (10.10.10.9) to the existed kubernetes
  $(basename "$0") 10.10.10.9 root password 1.16.2 18.09.7 10.10.10.100:8443 10.10.10.100:2379 etcd-first-node.com k8s-first-node.com join worker ipvs systemd hub.docker.com /etc/etcd/pki 10.10.10.9 10.10.10.10 10.10.10.11
EOF
  exit 1
fi

source lib/fmt.sh
source lib/assert.sh
source lib/pkg.sh
source lib/ssh.sh
source lib/service.sh

HOTS_NAME=${1}
USER_NAME=${2}
PASSWORD=${3}
K8S_VERSION=${4}
DOCKER_VERSION=${5}
SLB_KUBE_API_ADDR=${6}
SLB_ETCD_ADDR=${7}
ETCD_NODE=${8}
K8S_MASTER_NODE=${9}
ACTION=${10}
ROLE=${11}
PROXY=${12}
CGROUP_DRIVER=${13}
DOCKER_REGISTRY=${14}
ETCD_CERT_DIR=${15}
shift 15
NTP_SERVERS=$@

ETCD_USER=${USER_NAME}
ETCD_PASSWORD=${PASSWORD}

# Dependency
BOOTSTRAP_FILE="bootstrap.sh"
INSTALL_DOCKER_FILE="install-docker.sh"
# Dir
K8S_ROOT_DIR="/etc/kubernetes"
K8S_CERT_DIR="${K8S_ROOT_DIR}/pki"
K8S_CONF_DIR="${K8S_ROOT_DIR}"
KUBEADM_CONFIG="${K8S_CONF_DIR}/kubeadm-config.yaml"
# etcd certs on the etcd server
ETCD_CA_ON_ETCD_SERVER="${ETCD_CERT_DIR}/ca.pem"
ETCD_CLIENT_CERT_ON_ETCD_SERVER="${ETCD_CERT_DIR}/etcd.pem"
ETCD_CLIENT_KEY_ON_ETCD_SERVER="${ETCD_CERT_DIR}/etcd-key.pem"
# etcd certs stored path on k8s server
LOCAL_ETCD_CA="${K8S_CERT_DIR}/etcd/ca.pem"
mkdir -p "${K8S_CERT_DIR}/etcd"
LOCAL_ETCD_CLIENT_CERT="${K8S_CERT_DIR}/etcd.pem"
LOCAL_ETCD_CLIENT_CERT_KEY="${K8S_CERT_DIR}/etcd-key.pem"

# networking

# k8s service CIDR (SVC_CIDR): 10.10.0.0/16
# 10.10.0.0/16   00001010 00001010 00000000 00000000
#                -----------------
# 最小地址是      00001010 00001010 00000000 00000000 -> 10.10.0.0
# 最大地址是      00001010 00001010 11111111 11111111 -> 10.10.255.255
# 子网掩码是      11111111 11111111 00000000 00000000 -> 255.255.0.0
# 地址数量是      (255-0+1)*(255-0+1) = 256*256 = 65536 个
SVC_CIDR="10.10.0.0/16"

# k8s pod CIDR (POD_CIDR): 172.172.0.0/16, it is a Calico default. Substitute or remove for your CNI provider
# 172.172.0.0/16 10101100 10101100 00000000 00000000
#                -----------------
# 最小地址是      10101100 10101100 00000000 00000000 -> 172.172.0.0
# 最大地址是      10101100 10101100 11111111 11111111 -> 172.172.255.255
# 子网掩码是      11111111 11111111 00000000 00000000 -> 255.255.0.0
# 地址数量是      (255-0+1)*(255-0+1) = 256*256 = 65536 个
POD_CIDR="172.172.0.0/16"

DNS_DOMAIN="cluster.local"
# kubernetes binary and service
K8S_SERVICE=("kubelet")
K8S_BINARY=("kubectl" "kubeadm")

# Install docker and run bootstrap
# reinstall or keep
# TODO: upgrade docker
REINSTALL_DOCKER=keep
# Default is run
# true or false
RUN_BOOTSTRAP=true


function k8s::install::init() {
    ssh::init
    ssh::gen_pub_key
    ssh::keep_alive
}

function k8s::install::remote_exec() {
    local host=${1}
    local user=${2}
    local script=${3}
    shift 3
    local parameters=$@
    local lib_folder="lib"
    local remote_exec_folder="/tmp"

    fmt::info "Run ${script} on ${host}"
    assert::file_existed ${script}
    chmod +x ${script}

    # 拷贝 lib 文件夹到远端机器
    ssh::push ${host} ${user} ${lib_folder} ${remote_exec_folder}
    # 拷贝脚本到远端机器
    ssh::push ${host} ${user} ${script} ${remote_exec_folder}
    # 设置文件权限
    ssh::exec ${host} ${user} "chmod +x ${remote_exec_folder}/${script}"

    fmt::remote ${host} "${script} started"
    ssh::exec ${host} ${user} "cd ${remote_exec_folder} && ${remote_exec_folder}/${script} ${parameters[@]}"
    fmt::remote ${host} "${script} finished"
}

function k8s::install::install_k8s() {
    local host=${1}
    local user=${2}
    # array
    local bins=${3}
    # array
    local srvs=${4}
    local version=${5}
    local repo_file="kubernetes.repo"
    local script_target="/etc/yum.repos.d/kubernetes.repo"

    fmt::info "Install kubernetes"
    fmt::info "Phase 1 - create kubernetes repo"
    # Aliyun Mirro
#    cat > ${repo_file} <<EOF
#[kubernetes]
#name=Kubernetes - Aliyun
#baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
#enabled=1
#gpgcheck=0
#repo_gpgcheck=0
#gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
#       http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
#EOF
    # Official Mirro
    cat > ${repo_file} <<EOF
[kubernetes]
name=Kubernetes - Official
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
    if [ "${host}" == "localhost" ] || [ "${host}" == "127.0.0.1" ]; then
        cp ${repo_file} ${script_target}
        fmt::info "Phase 2 - install services on ${host}"
        for srv in ${srvs[@]}; do
            yum remove -y ${srv}
            yum install -y ${srv}-${version}
            # kubelet should be stop before kubeadm pre-flight check: [ERROR Port-10250]: Port 10250 is in use
            systemctl daemon-reload && systemctl enable ${srv} && systemctl stop ${srv}
        done
        fmt::info "Phase 3 - install binaries on ${host}"
        for bin in ${bins[@]}; do
            yum remove -y ${bin}
            pkg::install ${bin}-${version}
        done
    else
        ssh::push ${host} ${user} ${repo_file} ${script_target}
        fmt::info "Phase 2 - install services on ${host}"
        for srv in ${srvs[@]}; do
            ssh::exec ${host} ${user} "yum remove -y ${srv}; yum install -y ${srv}-${version}"
            # kubelet should be stop before kubeadm pre-flight check: [ERROR Port-10250]: Port 10250 is in use
            ssh::exec ${host} ${user} "systemctl daemon-reload && systemctl enable ${srv} && systemctl stop ${srv}"
            fmt::ok "Service ${srv} has been installed on ${host}"
        done
        fmt::info "Phase 3 - install binaries on ${host}"
        for bin in ${bins[@]}; do
            # ssh::exec ${host} ${user} "if ! (hash ${bin}) >/dev/null 2>&1; then yum install -y ${bin}-${version}; fi;"
            ssh::exec ${host} ${user} "yum remove -y ${bin}; yum install -y ${bin}-${version}"
            fmt::ok "Binary ${bin} has been installed on ${host}"
        done
    fi
    fmt::print "Kubernetes install on ${host}: "
    fmt::ok "Completed"
}

# Create kubeadm config file
# Details:
# Doc: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/control-plane-flags
# kubeadm API: https://godoc.org/k8s.io/kubernetes/cmd/kubeadm/app/apis/kubeadm/v1beta2#ClusterConfiguration
# kube-proxy API: https://godoc.org/k8s.io/kube-proxy/config/v1alpha1
# kubelet API: https://godoc.org/k8s.io/kubernetes/pkg/kubelet/apis/config#KubeletConfiguration
function k8s::install::create_kubeadm_config() {
    local config=${1}
    local k8s_version=${2}
    local slb_api_addr=${3}
    local slb_etcd_addr=${4}
    local svc_cidr=${5}
    local pod_cidr=${6}
    local dns_domain=${7}
    # etcd ca file path on k8s node
    local etcd_ca_file=${8}
    # etcd cert file path on k8s node
    local etcd_client_cert=${9}
    # etcd cert key file path on k8s node
    local etcd_client_key=${10}
    local k8s_proxy_mode=${11}
    local k8s_cgroup_driver=${12}

    local api_host=$(echo ${slb_api_addr} | awk -F ":" '{print $1}')
    fmt::info "Create kubeadm config ${config}"
    cat > ${config} <<EOF
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: ${k8s_version}
controlPlaneEndpoint: "${slb_api_addr}"
apiServer:
  certSANs:
  - "${api_host}"
etcd:
  external:
    endpoints:
    - "https://${slb_etcd_addr}"
    caFile: ${etcd_ca_file}
    certFile: ${etcd_client_cert}
    keyFile: ${etcd_client_key}
networking:
  serviceSubnet: "${svc_cidr}"
  podSubnet: "${pod_cidr}"
  dnsDomain: "${dns_domain}"
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ${k8s_proxy_mode}
ipvs:
  minSyncPeriod: 0s
  # syncPeriod is the period that ipvs rules are refreshed (e.g. '5s', '1m', '2h22m').  Must be greater than 0.
  syncPeriod: 30s
  # ipvs scheduler
  # rr：轮询
  # lc：最少连接数
  # dh：目的地址哈希
  # sh：源地址哈希
  # sed：最短期望延时
  # nq：从不排队
  scheduler: rr
iptables:
  masqueradeAll: false
  masqueradeBit: 14
  minSyncPeriod: 0s
  syncPeriod: 30s
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: ${k8s_cgroup_driver}
EOF
}

# 从 etcd server 拉取 certs
function k8s::install::pull_etcd_certs() {
    local etcd_host=${1}
    local etcd_user=${2}
    local etcd_ca=${3}
    local etcd_cert=${4}
    local etcd_key=${5}
    local k8s_etcd_ca=${6}
    local k8s_etcd_cert=${7}
    local k8s_etcd_key=${8}

    fmt::info "Pull etcd certs from etcd server ${etcd_host}"
    ssh::pull ${etcd_host} ${etcd_user} ${etcd_ca} ${k8s_etcd_ca}
    ssh::pull ${etcd_host} ${etcd_user} ${etcd_cert} ${k8s_etcd_cert}
    ssh::pull ${etcd_host} ${etcd_user} ${etcd_key} ${k8s_etcd_key}
    fmt::ok "All etcd certs were pulled stored"
}

# 把 etcd certs 分发到各 node
function k8s::install::push_etcd_certs() {
    local host=${1}
    local user=${2}
    local local_etcd_ca=${3}
    local local_etcd_cert=${4}
    local local_etcd_key=${5}
    # /etc/kubernetes/pki
    local target_cert_path=${6}

    fmt::info "Push etcd certs to kubernetes node ${host}"
    assert::file_existed ${local_etcd_ca}
    assert::file_existed ${local_etcd_cert}
    assert::file_existed ${local_etcd_key}
    ssh::exec ${host} ${user} "mkdir -p ${target_cert_path}/etcd"
    ssh::push ${host} ${user} ${local_etcd_ca} "${target_cert_path}/etcd"
    ssh::push ${host} ${user} ${local_etcd_cert} ${target_cert_path}
    ssh::push ${host} ${user} ${local_etcd_key} ${target_cert_path}
    fmt::ok "All etcd certs were pushed to kubernetes node ${host}"
}

# 从 kubernetes server 拉取 certs
function k8s::install::pull_k8s_certs() {
    local host=${1}
    local user=${2}
    local cert_path=${3}
    local ca=${4}
    local ca_key=${5}
    local sa=${6}
    local sa_key=${7}
    local proxy_ca=${8}
    local proxy_ca_key=${9}

    fmt::info "Pull kubernetes certs from ${host}"
    ssh::pull ${host} ${user} ${ca} ${cert_path}
    ssh::pull ${host} ${user} ${ca_key} ${cert_path}
    ssh::pull ${host} ${user} ${sa} ${cert_path}
    ssh::pull ${host} ${user} ${sa_key} ${cert_path}
    ssh::pull ${host} ${user} ${proxy_ca} ${cert_path}
    ssh::pull ${host} ${user} ${proxy_ca_key} ${cert_path}
    fmt::ok "All certs were stored to ${cert_path}"
}

# 从 kubernetes server 拉取 certs
function k8s::install::push_k8s_certs() {
    local host=${1}
    local user=${2}
    local cert_path=${3}
    local ca=${4}
    local ca_key=${5}
    local sa=${6}
    local sa_key=${7}
    local proxy_ca=${8}
    local proxy_ca_key=${9}
    # master or worker
    local role=${10}

    fmt::info "push kubernetes certs to ${host}:${cert_path}"
    assert::file_existed ${ca}
    assert::file_existed ${ca_key}
    assert::file_existed ${sa}
    assert::file_existed ${sa_key}
    assert::file_existed ${proxy_ca}
    assert::file_existed ${proxy_ca_key}
    if [ ${role} == "master" ]; then
        ssh::push ${host} ${user} ${ca} ${cert_path}
        ssh::push ${host} ${user} ${ca_key} ${cert_path}
    fi
    ssh::push ${host} ${user} ${sa} ${cert_path}
    ssh::push ${host} ${user} ${sa_key} ${cert_path}
    ssh::push ${host} ${user} ${proxy_ca} ${cert_path}
    ssh::push ${host} ${user} ${proxy_ca_key} ${cert_path}
    fmt::ok "All certs were push to ${host}:${cert_path}"
}

# 把 kubeadm config 分发到各 node
function k8s::install::push_kubeadm_config() {
    local host=${1}
    local user=${2}
    local config=${3}
    local target_path=${4}

    fmt::info "Push kubeadm config to ${host}"
    assert::file_existed ${config}
    ssh::exec ${host} ${user} "mkdir -p ${target_path}"
    ssh::push ${host} ${user} ${config} ${target_path}
    fmt::ok "kubeadm config was pushed to kubernetes node ${host}"
}

# 从 node 拉取 kube-config
function k8s::install::pull_kube_config() {
    local host=${1}
    local user=${2}
    # /etc/kubernetes
    local config_dir=${3}

    fmt::info "Pull kubeconfig from kubernetes server ${host}"
    mkdir -p $HOME/.kube
    mkdir -p ${config_dir}
    ssh::pull ${host} ${user} "${config_dir}/admin.conf" "$HOME/.kube/config"
    ssh::pull ${host} ${user} "${config_dir}/admin.conf" ${config_dir}
    fmt::ok "admin.conf was stored to $HOME/.kube/config and ${config_dir}"
}

# 把 kube-config 分发到各 node
function k8s::install::push_kube_config() {
    local host=${1}
    local user=${2}
    # /etc/kubernetes/admin.conf
    local kube_config_file=${3}
    # ~/.kube/config
    local target_file=${4}

    fmt::info "Push kube-config to ${host}"
    assert::file_existed ${kube_config_file}
    ssh::push ${host} ${user} ${kube_config_file} ${target_file}
    fmt::ok "kube-config was pushed to kubernetes node ${host}"
}

# 新建集群
function k8s::install::new() {
    local host=${1}
    local user=${2}
    local k8s_config_dir=${3}
    local kubeadm_config_dir=${4}
    local k8s_cert_path=${5}

    fmt::info "Node ${host} will be the first control node in cluster"
    fmt::info "Create admin kubeconfig file on ${host}"
    ssh::exec ${host} ${user} "kubeadm init --config ${kubeadm_config_dir}"
    ssh::exec ${host} ${user} "mkdir -p $HOME/.kube"
    ssh::exec ${host} ${user} "cp -i ${k8s_config_dir}/admin.conf $HOME/.kube/config"
    ssh::exec ${host} ${user} "chown $(id -u):$(id -g) $HOME/.kube/config"
    k8s::install::pull_kube_config ${host} ${user} ${k8s_config_dir}

    # 拉取 cert 回来
    # 在执行 join 的时候会用到拉取回来的 cert
    k8s::install::pull_k8s_certs ${host} ${user} ${k8s_cert_path} \
     "${k8s_cert_path}/ca.crt" \
     "${k8s_cert_path}/ca.key" \
     "${k8s_cert_path}/sa.pub" \
     "${k8s_cert_path}/sa.key" \
     "${k8s_cert_path}/front-proxy-ca.crt" \
     "${k8s_cert_path}/front-proxy-ca.key"
}

function k8s::install::join() {
    local host=${1}
    local user=${2}
    # master or worker
    local role=${3}
    # /etc/kubernetes
    local kube_config_path=${4}
    # /etc/kubernetes/pki/
    local k8s_cert_path=${5}
    local slb_api_addr=${6}

    fmt::info "Node ${1} [${role}] will be joined to cluster"
    ssh::exec ${host} ${user} "mkdir -p $HOME/.kube"

    # 确保 admin.conf 可用
    k8s::install::push_kube_config ${host} ${user} "${kube_config_path}/admin.conf" "/tmp"
    ssh::exec ${host} ${user} "rm -f $HOME/.kube/config && cp /tmp/admin.conf $HOME/.kube/config"

    # 确保 k8s_cert_path 内有可用的 cert
    k8s::install::push_k8s_certs ${host} ${user} ${k8s_cert_path} \
     "${k8s_cert_path}/ca.crt" \
     "${k8s_cert_path}/ca.key" \
     "${k8s_cert_path}/sa.pub" \
     "${k8s_cert_path}/sa.key" \
     "${k8s_cert_path}/front-proxy-ca.crt" \
     "${k8s_cert_path}/front-proxy-ca.key" \
     ${role}

    local ca_sha256_hash=$(openssl x509 -pubkey -in ${k8s_cert_path}/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    # token 一般 48 小时过期
    kubeadm token create
    local token=$(kubeadm token list | awk '{print $1}' | sed -n '2p')
    local cmd="kubeadm join ${slb_api_addr} --token ${token} --discovery-token-ca-cert-hash sha256:${ca_sha256_hash}"
    if [ ${role} == "master" ]; then
        cmd="${cmd} --control-plane"
    fi
    fmt::debug "CMD: ${cmd}"
    ssh::exec ${host} ${user} "${cmd}"
}

function Main() {
    fmt::info "Init kubernetes installation"
    k8s::install::init

    # 登录到一台 etcd 节点上, 拉取需要的证书
    ssh::passwordless ${ETCD_NODE} ${ETCD_USER} ${ETCD_PASSWORD}
    k8s::install::pull_etcd_certs \
     ${ETCD_NODE} \
     ${ETCD_USER} \
     ${ETCD_CA_ON_ETCD_SERVER} \
     ${ETCD_CLIENT_CERT_ON_ETCD_SERVER} \
     ${ETCD_CLIENT_KEY_ON_ETCD_SERVER} \
     ${LOCAL_ETCD_CA} \
     ${LOCAL_ETCD_CLIENT_CERT} \
     ${LOCAL_ETCD_CLIENT_CERT_KEY}

    # 在 HOTS_NAME 上执行 bootstrap
    ssh::passwordless ${HOTS_NAME} ${USER_NAME} ${PASSWORD}
    if [ "${RUN_BOOTSTRAP}" == "true" ]; then
        k8s::install::remote_exec ${HOTS_NAME} ${USER_NAME} ${BOOTSTRAP_FILE} ${DOCKER_REGISTRY} "${NTP_SERVERS[*]}"
    fi

    # 在 HOTS_NAME 上安装指定版本的 docker
    k8s::install::remote_exec ${HOTS_NAME} ${USER_NAME} ${INSTALL_DOCKER_FILE} ${DOCKER_VERSION} ${REINSTALL_DOCKER}

    # 在 HOTS_NAME 上安装指定版本的 kubelet, kubeadm, kubelet
    k8s::install::install_k8s ${HOTS_NAME} ${USER_NAME} "${K8S_BINARY[*]}" "${K8S_SERVICE[*]}" ${K8S_VERSION}

    # 把 etcd certs 分发到 HOTS_NAME 上 的 K8S_CERT_DIR 文件夹
    k8s::install::push_etcd_certs ${HOTS_NAME} ${USER_NAME} ${LOCAL_ETCD_CA} ${LOCAL_ETCD_CLIENT_CERT} ${LOCAL_ETCD_CLIENT_CERT_KEY} ${K8S_CERT_DIR}

    # 把 kubeadm config 安装到本地
    k8s::install::create_kubeadm_config ${KUBEADM_CONFIG} \
      ${K8S_VERSION} \
      ${SLB_KUBE_API_ADDR} \
      ${SLB_ETCD_ADDR} \
      ${SVC_CIDR} \
      ${POD_CIDR} \
      ${DNS_DOMAIN} \
      ${LOCAL_ETCD_CA} \
      ${LOCAL_ETCD_CLIENT_CERT} \
      ${LOCAL_ETCD_CLIENT_CERT_KEY} \
      ${PROXY} \
      ${CGROUP_DRIVER}

    # 推送 kubeadm-config.yaml 到 HOTS_NAME
    k8s::install::push_kubeadm_config ${HOTS_NAME} ${USER_NAME} ${KUBEADM_CONFIG} ${K8S_CONF_DIR}

    if [ "${ACTION}" == "new" ]; then
        k8s::install::new ${HOTS_NAME} ${USER_NAME} ${K8S_CONF_DIR} ${KUBEADM_CONFIG} ${K8S_CERT_DIR}
    else
        ssh::passwordless ${K8S_MASTER_NODE} ${USER_NAME} ${PASSWORD}
        k8s::install::pull_kube_config ${K8S_MASTER_NODE} ${USER_NAME} ${K8S_CONF_DIR}
        k8s::install::pull_k8s_certs ${K8S_MASTER_NODE} ${USER_NAME} ${K8S_CERT_DIR} \
            "${K8S_CERT_DIR}/ca.crt" \
            "${K8S_CERT_DIR}/ca.key" \
            "${K8S_CERT_DIR}/sa.pub" \
            "${K8S_CERT_DIR}/sa.key" \
            "${K8S_CERT_DIR}/front-proxy-ca.crt" \
            "${K8S_CERT_DIR}/front-proxy-ca.key"
        k8s::install::join ${HOTS_NAME} ${USER_NAME} ${ROLE} ${K8S_CONF_DIR} ${K8S_CERT_DIR} ${SLB_KUBE_API_ADDR}
    fi

    fmt::info "Summary"
    ssh::exec ${HOTS_NAME} ${USER_NAME} "kubectl get nodes"
}

Main
