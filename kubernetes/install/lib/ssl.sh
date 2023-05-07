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

# This script is used for tool cfssl
# You must install cfssl (https://github.com/cloudflare/cfssl.git)

# The directory test-infra/kubernetes/install of project test-infra
# You must exec script at directory test-infra/kubernetes/install
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE}")/.." && pwd -P)"

source "${ROOT_DIR}/lib/fmt.sh"

# ssl::mk::ca 87600h kubernetes kubernetes Sichuan Sichuan k8s System
function ssl::mk::ca() {
    local expiry=${1}
    local profile_name=${2}
    local cn_name=${3}
    local st_name=${4}
    local l_name=${5}
    local o_name=${6}
    local ou_name=${7}

    cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "${expiry}"
    },
    "profiles": {
      "${profile_name}": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "${expiry}"
      }
    }
  }
}
EOF

    cat > ca-csr.json <<EOF
{
  "CN": "${cn_name}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "${st_name}",
      "L": "${l_name}",
      "O": "${o_name}",
      "OU": "${ou_name}"
    }
  ],
  "ca": {
    "expiry": "${expiry}"
 }
}
EOF
    cfssl gencert -initca ca-csr.json | cfssljson -bare ca
    ls ca*
}

# ssl::mk::cert etcd etcd Sichuan Sichuan k8s System ca.pem ca-key.pem ca-config.json kubernetes 127.0.0.1 10.62.0.5 slb.api.com
# ssl::mk::cert kubernetes kubernetes Sichuan Sichuan k8s System ca.pem ca-key.pem ca-config.json kubernetes 127.0.0.1 10.62.0.5 slb.api.com
function ssl::mk::cert() {
    local cert_name=${1}
    local cn_name=${2}
    local st_name=${3}
    local l_name=${4}
    local o_name=${5}
    local ou_name=${6}
    local ca_path=${7}
    local ca_key_path=${8}
    local ca_json_path=${9}
    local profile_name=${10}
    shift 10
    local hosts=$@

    cat > ${cert_name}-csr.json <<EOF
{
  "CN": "${cn_name}",
  "hosts": [
EOF

    for host in ${hosts[@]}; do
        cat >> ${cert_name}-csr.json <<EOF
    "${host}",
EOF
    done

    # 去掉最后一个逗号
    local last_line_number=$(cat ${cert_name}-csr.json | grep -n , | tail -1 | awk -F ":" '{print $1}')
    if [ ${last_line_number} -lt 1 ]; then
        fmt::fatal "Line number ${last_line_number} must be > 0"
    fi
    sed -i "${last_line_number}s/,//" ${cert_name}-csr.json

    cat >> ${cert_name}-csr.json <<EOF
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "${st_name}",
      "L": "${l_name}",
      "O": "${o_name}",
      "OU": "${ou_name}"
    }
  ]
}
EOF
    cfssl gencert -ca=${ca_path} \
      -ca-key=${ca_key_path} \
      -config=${ca_json_path} \
      -profile=${profile_name} ${cert_name}-csr.json | cfssljson -bare ${cert_name}

    ls ${cert_name}*
}

