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


if [ "$#" -lt 5 ] || [ "${1}" == "--help" ]; then
  cat <<EOF

Description:
Remove a node from kubernetes cluster

Usage: $(basename "$0") <user> <password> <external etcd> <uninstall> <node 1> <node 2> ......
  <user>             user name of node
  <password>         password of node
  <external etcd>    true | false - The etcd cluster is in the kubernetes cluster or an external
  <uninstall>        true | false - Uninstall kubeadm, kubelet, kubectl or keep
  <node 1>           node name, kubectl get node
  <node 2>           node name, kubectl get node
  ......             node name, kubectl get node

Examples:
  # Remove a node from kubernetes cluster
  $(basename "$0") root password true true 10.10.10.6 10.10.10.7 10.10.10.8

EOF
  exit 1
fi

source lib/fmt.sh
source lib/assert.sh
source lib/pkg.sh
source lib/ssh.sh

USER_NAME=${1}
PASSWORD=${2}
EXTERNAL_ETCD=${3}
UNINSTALL_PACKAGES=${4}
shift 4
K8S_NODES=$@

function k8s::uninstall::init() {
    ssh::init
    ssh::gen_pub_key
    ssh::keep_alive
}

function k8s::uninstall::remove_k8s_node() {
    assert::obj_not_null ${1}
    assert::obj_not_null ${2}
    assert::obj_not_null ${3}
    assert::obj_not_null ${4}
    local node_name=${1}
    local user=${2}
    local external_etcd=${3}
    local uninstall_k8s_packages=${4}
    local data_path=/etc/kubernetes
    local kubelet_data_path=/var/lib/kubelet
    fmt::info "Phase 1 - drain node ${1}"
    kubectl drain ${1} --delete-local-data --force --ignore-daemonsets
    fmt::info "Phase 2 - delete node ${1}"
    kubectl delete node ${1}
    fmt::info "Phase 3 - stop kubelet service"
    ssh::exec ${node_name} ${user} "systemctl daemon-reload && systemctl stop kubelet"
    fmt::info "Phase 4 - kubeadm reset"
    # TODO: auto type y
    ssh::exec ${node_name} ${user} "echo y | kubeadm reset"
    fmt::info "Phase 5 - removing k8s containers"
    images=$(ssh::exec ${node_name} ${user} docker ps -a | grep k8s | awk '{print $1}')
    for image in ${images[@]};do
        fmt::process "stop container ${image}"
        ssh::exec ${node_name} ${user} "docker stop ${image}"
        fmt::ok "Done"
        fmt::process "remove container ${image}"
        ssh::exec ${node_name} ${user} "docker rm ${image}"
        fmt::ok "Done"
    done
    fmt::println "Check k8s containers"
    ssh::exec ${node_name} ${user} "docker ps -a"
    fmt::info "Phase 6 - restart docker"
    ssh::exec ${node_name} ${user} "systemctl restart docker"
    fmt::info "Phase 7 - remove kubernetes data path ${data_path}"
    ssh::exec ${node_name} ${user} "rm -rf ${data_path}"
    ssh::check_dir_exist ${node_name} ${user} "${data_path}"
    fmt::info "Phase 8 - remove kubelet data path ${kubelet_data_path}"
    ssh::exec ${node_name} ${user} "rm -rf ${kubelet_data_path}"
    ssh::check_dir_exist ${node_name} ${user} "${kubelet_data_path}"
    fmt::info "Phase 9 - remove default kube-config folder $HOME/.kube/"
    ssh::exec ${node_name} ${user} "rm -rf $HOME/.kube/"
    ssh::check_dir_exist ${node_name} ${user} "$HOME/.kube/"
    fmt::info "Phase 10 - remove /etc/systemd/system/kubelet.service.d/20-etcd-service-manager.conf"
    if [ "${external_etcd}" == "true" ];then
        ssh::exec ${node_name} ${user} "rm -f /etc/systemd/system/kubelet.service.d/20-etcd-service-manager.conf"
    fi
    fmt::info "Phase 11 - uninstall packages: kubeadm, kubelet, kubectl"
    if [ "${uninstall_k8s_packages}" == "true" ];then
        ssh::exec ${node_name} ${user} "yum remove kubectl.x86_64 -y"
        ssh::exec ${node_name} ${user} "yum remove kubeadm.x86_64 -y"
        ssh::exec ${node_name} ${user} "yum remove kubelet.x86_64 -y"
    else
       fmt::ok "Script set uninstall=${uninstall_k8s_packages}, skip uninstall packages"
    fi
    fmt::info "Phase 12 - remove rules of iptable and ipvs"
    ssh::exec ${node_name} ${user} "iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X"
    ssh::exec ${node_name} ${user} "ipvsadm --clear"
    fmt::info "Phase 13 - remove kube-config file"
    ssh::exec ${node_name} ${user} "rm -f ~/.kube/config"

    fmt::ok "Node ${node_name} has been removed"
}

k8s::uninstall::init
for node in ${K8S_NODES[@]};do
    ssh::passwordless ${node} ${USER_NAME} ${PASSWORD}
    k8s::uninstall::remove_k8s_node ${node} ${USER_NAME} ${EXTERNAL_ETCD} ${UNINSTALL_PACKAGES}
done

