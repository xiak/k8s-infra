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
Make calico.yaml

Usage: $(basename "$0") <etcd node> <etcd user> <etcd password> <etcd endpoint> <etcd certs path> <ipv4 cidr> <calico template file>
  <etcd node>               one of the etcd node in etcd cluster
  <etcd user>               etcd node user
  <etcd password>           etcd node password
  <etcd endpoint>           etcd cluster endpoint
  <etcd certs path>         etcd certs path
  <ipv4 cidr>               the same as pod cidr of k8s
  <calico template file>    calico.yaml template

Examples:
  # Not use VIP
  $(basename "$0") 10.10.10.3 root password https://10.10.10.3:2379,https://10.10.10.4:2379,https://10.10.10.5:2379 /etc/etcd/pki 10.10.0.0/24 calico-template.yaml
  # Use VIP https://10.10.10.100:2379 as the endpoint of ETCD cluster
  $(basename "$0") 10.10.10.3 root password https://10.10.10.100:2379 /etc/etcd/pki 10.10.0.0/24 calico-template.yaml

EOF
  exit 1
fi

source lib/fmt.sh
source lib/ssh.sh
source lib/assert.sh

ETCD_NODE=${1}
ETCD_NODE_USER=${2}
ETCD_NODE_PASSWORD=${3}
ETCD_ENDPOINT=${4}
ETCD_CERTS_PATH=${5}
IPV4_CIDR=${6}
CALICO_TEMPLATE_FILE=${7}

assert::file_existed ${CALICO_TEMPLATE_FILE}

ETCD_CA="${ETCD_CERTS_PATH}/ca.pem"
ETCD_CERT="${ETCD_CERTS_PATH}/etcd.pem"
ETCD_CERT_KEY="${ETCD_CERTS_PATH}/etcd-key.pem"

mkdir -p ${ETCD_CERTS_PATH}

fmt::info "Initialization"
ssh::passwordless ${ETCD_NODE} ${ETCD_NODE_USER} ${ETCD_NODE_PASSWORD}

fmt::info "Pull etcd certs"
ssh::pull ${ETCD_NODE} ${ETCD_NODE_USER} ${ETCD_CA} ${ETCD_CERTS_PATH}
ssh::pull ${ETCD_NODE} ${ETCD_NODE_USER} ${ETCD_CERT} ${ETCD_CERTS_PATH}
ssh::pull ${ETCD_NODE} ${ETCD_NODE_USER} ${ETCD_CERT_KEY} ${ETCD_CERTS_PATH}

assert::file_existed ${ETCD_CA}
assert::file_existed ${ETCD_CERT}
assert::file_existed ${ETCD_CERT_KEY}

fmt::info "Make calico.yaml"
__TLS_ETCD_KEY__=$(cat ${ETCD_CERT_KEY} | base64 -w 0)
__TLS_ETCD_CERT__=$(cat ${ETCD_CERT} | base64 -w 0)
__TLS_ETCD_CA__=$(cat ${ETCD_CA} | base64 -w 0)

cp ${CALICO_TEMPLATE_FILE} calico.yaml
sed -i "s#__M_ETCD_ENDPOINTS__#${ETCD_ENDPOINT}#g" calico.yaml
sed -i "s#__TLS_ETCD_CERT__#$__TLS_ETCD_CERT__#g" calico.yaml
sed -i "s#__TLS_ETCD_KEY__#$__TLS_ETCD_KEY__#g" calico.yaml
sed -i "s#__TLS_ETCD_CA__#$__TLS_ETCD_CA__#g" calico.yaml
sed -i "s#__IPV4_CIDR__#${IPV4_CIDR}#g" calico.yaml

kubectl apply -f calico.yaml
