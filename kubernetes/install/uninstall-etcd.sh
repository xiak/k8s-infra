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
Uninstall etcd cluster

Usage: $(basename "$0") <user> <password> <etcd work dir> <etcd bin dir> <node 1> <node 2> ......
  <user>             user name of node
  <password>         password of node
  <etcd work dir>    etcd work dir. default is /etc/etcd
  <etcd bin dir>     etcd bin dir. default is /usr/local/bin
  <node 1>           etcd node
  <node 2>           etcd node
  ......             etcd node

Examples:
  $(basename "$0") root password /etc/etcd /usr/local/bin 10.10.10.3 10.10.10.4 10.10.10.5

EOF
  exit 1
fi

source lib/ssh.sh

USER_NAME=${1}
PASSWORD=${2}
ETCD_WORK_DIR=${3}
ETCD_BIN_DIR=${4}
shift 4
ETCD_NODES=$@

ETCD_DATA_DIR="${ETCD_WORK_DIR}/data"
ETCD_WAL_DIR="${ETCD_WORK_DIR}/wal"
ETCD_CERT_DIR="${ETCD_WORK_DIR}/pki"

ETCD_SERVICE_NAME=etcd

ssh::init
ssh::gen_pub_key
ssh::keep_alive

for node in ${ETCD_NODES[@]}; do
    ssh::passwordless ${node} ${USER_NAME} ${PASSWORD}
    # Stop and disable service
    ssh::exec ${node} ${USER_NAME} "systemctl stop ${ETCD_SERVICE_NAME} && systemctl disable ${ETCD_SERVICE_NAME}"
    ssh::exec ${node} ${USER_NAME} "rm -f /etc/systemd/system/etcd.service"
    ssh::exec ${node} ${USER_NAME} "rm -f /usr/lib/systemd/system/etcd.service"
    # Remove binary
    ssh::exec ${node} ${USER_NAME} "rm -f ${ETCD_BIN_DIR}/etcd && rm -f ${ETCD_BIN_DIR}/etcdctl"
    # Remove work dir
    ssh::exec ${node} ${USER_NAME} "rm -rf ${ETCD_DATA_DIR}"
    ssh::exec ${node} ${USER_NAME} "rm -rf ${ETCD_WAL_DIR}"
    ssh::exec ${node} ${USER_NAME} "rm -rf ${ETCD_CERT_DIR}"
done
