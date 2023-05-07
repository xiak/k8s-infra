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

if [ "$#" -lt 1 ] || [ "${1}" == "--help" ]; then
  cat <<EOF

Description:
Install external etcd cluster

Usage: $(basename "$0") <IP SAN 1> <IP SAN 2> ...
  <IP SAN 1>        IP
  <IP SNA 2>        IP
  ...               IP

Examples:
  $(basename "$0") jenkins.datadomain.com taas.datadomain.com taas.ccoe.lab.emc.com jenkins.dnd.ai

EOF
  exit 1
fi

IP_SAN=$@

# ASCII color codes
COLOR_GREEN="\033[32m"
COLOR_RED="\033[31m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_PURPLE="\033[35m"
COLOR_SKYBLUE="\033[36m"

# Reset color code
COLOR_CLEAR="\033[0m"

# Print and return
function fmt::println() {
    printf "${1}\n"
}

# Print
function fmt::print() {
    printf "${1}"
}

# Print process
# fmt::process "Begin"
# doSomething
# fmt::ok "Done"
# Output
# >>> Begin: Done
function fmt::process() {
    printf ">>> ${1}: "
}

# Print remote execution - yellow
# fmt::printh 10.62.232.66 "Hello World"
# Output
# 10.62.232.66: Hello World
function fmt::remote() {
    printf "${COLOR_YELLOW}${1}: ${2}${COLOR_CLEAR}\n"
}

# Print info msg - skyblue
# fmt::info "Hello"
# Output
# Hello
function fmt::info() {
    printf "${COLOR_SKYBLUE}INFO ${1}${COLOR_CLEAR}\n"
}

# Print debug msg - blue
# fmt::debug "Hello"
# Output
# Hello
function fmt::debug() {
    printf "${COLOR_PURPLE}DEBUG ${1}${COLOR_CLEAR}\n"
}

# Print error msg - red
# fmt::error "Hello"
# Output
# Hello
function fmt::error() {
    printf "${COLOR_RED}ERROR ${1}${COLOR_CLEAR}\n"
}

# Print warning msg - yellow
# fmt::warn "Hello"
# Output
# Hello
function fmt::warn() {
    printf "${COLOR_YELLOW}WARN ${1}${COLOR_CLEAR}\n"
}

# Print fatal msg and then exit script - red
# fmt::fatal "Hello"
# Output
# Hello
function fmt::fatal() {
    printf "${COLOR_RED}FATAL ${1}${COLOR_CLEAR}\n"
    exit 1
}

# Print well done msg - green
# fmt::ok "Done"
# Output
# Done
function fmt::ok() {
    printf "${COLOR_GREEN}${1}${COLOR_CLEAR}\n"
}

# Print well done msg - red
# fmt::fail "Fail"
# Output
# Fail
function fmt::fail() {
    printf "${COLOR_RED}${1}${COLOR_CLEAR}\n"
}

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


# 生成 ca.pem 和 ca-key.pem
fmt::info "Create ca.pem and ca-key.pem"
ssl::mk::ca 87600h jenkins jenkins Sichuan Sichuan jenkins System
# 生成 etcd.pem 和 etcd-key.pem
fmt::info "Create jenkins.pem and jenkins-key.pem"
ssl::mk::cert jenkins jenkins Sichuan Sichuan jenkins System ca.pem ca-key.pem ca-config.json jenkins 127.0.0.1 ${IP_SAN[@]}

