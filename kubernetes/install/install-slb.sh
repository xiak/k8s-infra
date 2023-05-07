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

if [ "$#" -lt 7 ] || [ "${1}" == "--help" ]; then
  cat <<EOF

Description:
Install soft load balancer cluster

Usage: $(basename "$0") <user> <password> <VIP> <VIP interface> <k8s api nodes> <etcd nodes> <node 1> <node 2> ......
  <user>             user name of node
  <password>         password of node
  <VIP>              Virtual ip address
  <VIP interface>    Ethernet device, eg ens160, eth0
  <k8s api nodes>    kubernetes api nodes, null or list
  <etcd nodes>       etcd nodes list, null or list
  <node 1>           lb node
  <node 2>           lb node
  ......             lb node

Examples:
  $(basename "$0") root changeme 10.6.6.6 ens160 "10.20.0.2 10.20.0.3" "10.30.0.2 10.30.0.3" 10.10.0.2 10.10.0.3 10.10.0.4 10.10.0.5 10.10.0.6
  $(basename "$0") root changeme 10.6.6.6 ens160 "null" "10.30.0.2 10.30.0.3" 10.10.0.2 10.10.0.3 10.10.0.4 10.10.0.5 10.10.0.6
  $(basename "$0") root changeme 10.6.6.6 ens160 "null" "null" 10.10.0.2 10.10.0.3 10.10.0.4 10.10.0.5 10.10.0.6

EOF
  exit 1
fi

source lib/fmt.sh
source lib/assert.sh
source lib/pkg.sh
source lib/ssh.sh
source lib/service.sh

USER_NAME=${1}
PASSWORD=${2}
VIP=${3}
VIP_INTERFACE=${4}
# k8s api server list, format $*
KUBE_API_SERVERS=${5}
# etcd node list, format $*
ETCD_SERVERS=${6}
shift 6
LOAD_BALANCER_CLUSTER=$@

# Configuration
HAPROXY_CONFIG=haproxy.cfg
DEFAULT_ROUTER_ID="ROUTER_1000000"
DEFAULT_VIRTUAL_ROUTER_ID=90
KEEPALIVED_DEFAULT_PRIORITY=100

#ETCD_SERVERS=("10.62.231.160" "10.62.229.105" "10.62.232.41")
#KUBE_API_SERVERS=("10.62.231.161" "10.62.232.42" "10.62.229.106")

function lb::install::init() {
    ssh::init
    ssh::gen_pub_key
    ssh::keep_alive
}

function lb::template() {
    local listen_name=${1}
    local bind_port=${2}
    local backend_port=${3}
    shift 3
    local service_nodes=$@
    local template="lb-template-${listen_name}"
    cat > ${template} << EOF
listen ${listen_name}
    bind 0.0.0.0:${bind_port}
    mode tcp
    option tcplog
    balance source
EOF
    for node in ${service_nodes[@]};do
    cat >> ${template} << EOF
    server ${node} ${node}:${backend_port} check inter 2000 fall 2 rise 2 weight 1
EOF
    done
    cat ${template}
}

function lb::k8s() {
    if [ "${KUBE_API_SERVERS}" == "-skip-k8s" ] || [ "${KUBE_API_SERVERS}" == "" ]; then
        return
    fi
    # TODO: port can be config
    lb::template "k8s_apiserver" "8443" "6443" ${KUBE_API_SERVERS[@]}
}

function lb::etcd() {
    if [ "${ETCD_SERVERS}" == "-skip-etcd" ] || [ "${ETCD_SERVERS}" == "" ]; then
        return
    fi
    # TODO: port can be config
    lb::template "etcd_cluster" "2379" "2379" ${ETCD_SERVERS[@]}
}

function lb::create_haproxy_config() {
    local config=${1}

    fmt::info "Create ${config}"
    cat > ${config} <<EOF
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /var/run/haproxy.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    nbproc 1

defaults
    log     global
    timeout connect 5000
    timeout client  10m
    timeout server  10m

listen admin_stats
    bind 0.0.0.0:10080
    mode http
    log 127.0.0.1 local0 err
    stats refresh 30s
    stats uri /status
    stats realm welcome login\ Haproxy
    stats auth admin:123456
    stats hide-version
    stats admin if TRUE

$(lb::k8s)

$(lb::etcd)

EOF
}

function lb::create_keepalived_config() {
    local vip=${1}
    local host=${2}
    local router_id=${3}
    local role=${4}
    local interface=${5}
    local virtual_router_id=${6}
    local priority=${7}
    local config=${8}

    fmt::info "Create ${config}"

    cat  > ${config} <<EOF
global_defs {
    router_id ${router_id}
}

vrrp_script haproxy_status_checker {
    script "killall -0 haproxy"
    interval 2
    weight -5
}

vrrp_instance vi_api_gateway {
    state ${role}
    interface ${interface}
    virtual_router_id ${virtual_router_id}
    priority ${priority}
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 666666
    }
    track_script {
        haproxy_status_checker
    }
    virtual_ipaddress {
        ${vip}
    }
}
EOF
}

function lb::run() {
    local host=${1}
    local user=${2}
    local interface=${3}
    local router_id=${4}
    local virtual_router_id=${5}
    local priority=${6}
    local vip=${7}
    local role=${8}
    local haproxy_file=${9:-haproxy.cfg}
    local keepalived_file="${10:-keepalived-${1}}"
    local kernal_file=lb.conf
    local haproxy_config_target="/etc/haproxy"
    local keepalived_config_target="/etc/keepalived/keepalived.conf"
    local kernal_config_target="/etc/sysctl.d/lb.conf"

    fmt::info "Install packages on ${host}"
    # psmisc: fuser, killall, pstree, pstree.x11
    ssh::exec ${host} ${user} "if ! (hash killall) >/dev/null 2>&1; then yum install -y psmisc; fi;"
    ssh::exec ${host} ${user} "if ! (hash haproxy) >/dev/null 2>&1; then yum install -y haproxy; fi;"
    ssh::exec ${host} ${user} "if ! (hash keepalived) >/dev/null 2>&1; then yum install -y keepalived; fi;"
    ssh::exec ${host} ${user} "if ! (hash ipvsadm) >/dev/null 2>&1; then yum install -y ipvsadm; fi;"

    fmt::info "Copy ${haproxy_file} to ${host}:/etc/haproxy"
    lb::create_haproxy_config ${haproxy_file}
    ssh::push ${host} ${user} ${haproxy_file} ${haproxy_config_target}
    lb::create_keepalived_config ${vip} ${host} ${router_id} ${role} ${interface} ${virtual_router_id} ${priority} ${keepalived_file}

    fmt::info "Copy ${keepalived_file} to ${host}:${keepalived_config_target}"
    ssh::push ${host} ${user} ${keepalived_file} ${keepalived_config_target}

    # TODO: 生产环境需要防火墙，这里需要改成开放某些端口
    fmt::info "Close firewall"
    ssh::exec ${host} ${user} "systemctl stop firewalld && systemctl disable firewalld"

    fmt::info "Disable SELinux"
    ssh::exec ${host} ${user} "setenforce 0 > /dev/null 2>&1"
    ssh::exec ${host} ${user} "sed -i 's/^\(SELINUX=\)enforcing$/\1disabled/' /etc/selinux/config"
    ssh::exec ${host} ${user} "cat /etc/selinux/config"

    fmt::info "Update kernal on ${host}"
    cat > ${kernal_file} <<EOF
net.ipv4.ip_forward = 1
net.ipv4.ip_nonlocal_bind = 1
EOF
    ssh::push ${host} ${user} ${kernal_file} ${kernal_config_target}
    ssh::exec ${host} ${user} "sysctl -p ${kernal_config_target}"

    fmt::info "Run haproxy on ${1}"
    ssh::exec ${host} ${user} "systemctl daemon-reload && systemctl enable haproxy && systemctl restart haproxy"

    fmt::info "Run keepalived on ${1}"
    ssh::exec ${host} ${user} "systemctl daemon-reload && systemctl enable keepalived && systemctl restart keepalived"

    service::remote::wait_until_active haproxy ${host} ${user} 10
    service::remote::wait_until_active keepalived ${host} ${user} 10
}

function main() {
    lb::install::init

    local keepalived_role="MASTER"
    local keepalived_priority=${KEEPALIVED_DEFAULT_PRIORITY}

    for node in ${LOAD_BALANCER_CLUSTER[@]}; do
        ssh::passwordless ${node} ${USER_NAME} ${PASSWORD}
        if [ ${keepalived_priority} -lt ${KEEPALIVED_DEFAULT_PRIORITY} ]; then
            keepalived_role="BACKUP"
        fi
        lb::run ${node} ${USER_NAME} ${VIP_INTERFACE} ${DEFAULT_ROUTER_ID} ${DEFAULT_VIRTUAL_ROUTER_ID} ${keepalived_priority} ${VIP} ${keepalived_role}
        keepalived_priority=$[keepalived_priority-1]
    done
}

main
fmt::info "Test VIP connection"
ping -c 6 ${VIP}
fmt::ok "ok"
