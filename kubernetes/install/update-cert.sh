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
Update certs

Usage: $(basename "$0") <user> <password>
  <user>             user name of node
  <password>         password of node

Examples:


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

KUBE_WORKSPACE="/etc/kubernetes"
KUBE_CERT_PATH="${KUBE_WORKSPACE}/pki"
#KUBE_CERTS="front-proxy-ca.crt,front-proxy-ca.key"
KUBE_CONFIG="admin.conf"

function k8s::cert::init() {
    ssh::init
    ssh::gen_pub_key
    ssh::keep_alive
}

function k8s::cert::update() {
    local host="${1}"
    local user="${2}"
    local password="${3}"

    ssh::passwordless "${host}" "${user}" "${password}"
    fmt::sub "copy certs to $host";
    scp ${KUBE_CERT_PATH}/{front-proxy-ca.crt,front-proxy-ca.key} "${user}@${host}:${KUBE_CERT_PATH}"
    fmt::sub "restart kubelet"
    ssh::exec "${host}" "${user}" "systemctl restart kubelet"
    fmt::sub "copy kubeconfig to $host";
    scp "${KUBE_WORKSPACE}/${KUBE_CONFIG}" "${user}@${host}:${KUBE_WORKSPACE}/${KUBE_CONFIG}"
    ssh::exec "${host}" "${user}" "rm -f ~/.kube/config; cp -i ${KUBE_WORKSPACE}/${KUBE_CONFIG} \$HOME/.kube/config; chown \$(id -u):\$(id -g) \$HOME/.kube/config"
    ssh::exec "${host}" "${user}" "kubectl cluster-info"
    fmt::ok "${host} done"
}

function main() {
    fmt::info "Start to update certs"
    hosts=$(kubectl get node | grep Ready | awk '{ print $1 }')
    for host in ${hosts[@]}; do
        k8s::cert::update "${host}" "${USER_NAME}" "${PASSWORD}"
    done
}

main
fmt::ok "All tasks have done"
