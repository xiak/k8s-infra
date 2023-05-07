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


if [ "$#" -lt 0 ] || [ "${1}" == "--help" ]; then
  cat <<EOF

Description:
Copy file /etc/hosts to all hosts which were defined in /etc/hosts

Usage: $(basename "$0")

Examples:
  # copy /tmp/hosts to each host which defined in /tmp/hosts
  $(basename "$0")

  # The /tmp/hosts file is like this
  10.198.137.91    k8s-bastion            root     pas@123a
  10.198.137.93    k8s-master-1           root     pas@123a
  10.198.137.94    k8s-master-2           root     pas@123a
  10.198.137.95    k8s-master-3           root     pas@123a
  10.198.137.96    k8s-slb-1              root     pas@123a
  10.198.137.97    k8s-slb-2              root     pas@123a
  10.198.137.98    k8s-slb-3              root     pas@123a
  10.198.137.171   k8s-etcd-1             root     pas@123a
  10.198.137.172   k8s-etcd-2             root     pas@123a
  10.198.137.173   k8s-etcd-3             root     pas@123a
  10.198.137.200   k8s-ceph-1             root     abc123
  10.198.137.201   k8s-ceph-2             root     abc123
  10.198.137.202   k8s-ceph-3             root     abc123
  10.198.137.203   k8s-ceph-4             root     abc123
  10.198.137.205   k8s-ceph-5             root     abc123
  10.198.137.206   k8s-ceph-6             root     abc123
  10.198.138.96    k8s-report             root     pas@123a
  10.198.138.150   k8s-dnd                root     pas@123a
  10.198.138.151   k8s-cp                 root     pas@123a
  10.198.138.152   k8s-dp                 root     pas@123a
  10.198.138.153   k8s-dash               root     pas@123a
  10.198.138.154   k8s-ceph-dashboard     root     pas@123a
  10.198.138.155   k8s-git                root     pas@123a
  10.198.138.156   k8s-hub                root     pas@123a
  10.198.138.158   k8s-infra              root     pas@123a


EOF
  exit 1
fi

source lib/ssh.sh
source lib/fmt.sh

# Generate /etc/hosts format file to ${dest_file}
function make::etchosts {
    local conf_file=${1}
    local dest_file=${2}

    fmt::info "Make /etc/hosts format file: ${dest_file}"
    cat > "${conf_file}" << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
10.198.137.91    k8s-bastion            root     pas@123a
10.198.137.93    k8s-master-1           root     pas@123a
10.198.137.94    k8s-master-2           root     pas@123a
10.198.137.95    k8s-master-3           root     pas@123a
10.198.137.96    k8s-slb-1              root     pas@123a
10.198.137.97    k8s-slb-2              root     pas@123a
10.198.137.98    k8s-slb-3              root     pas@123a
10.198.137.171   k8s-etcd-1             root     pas@123a
10.198.137.172   k8s-etcd-2             root     pas@123a
10.198.137.173   k8s-etcd-3             root     pas@123a
10.198.137.200   k8s-ceph-1             root     abc123
10.198.137.201   k8s-ceph-2             root     abc123
10.198.137.202   k8s-ceph-3             root     abc123
10.198.137.203   k8s-ceph-4             root     abc123
10.198.137.205   k8s-ceph-5             root     abc123
10.198.137.206   k8s-ceph-6             root     abc123
10.198.138.96    k8s-report             root     pas@123a
10.198.138.150   k8s-dnd                root     pas@123a
10.198.138.151   k8s-cp                 root     pas@123a
10.198.138.152   k8s-dp                 root     pas@123a
10.198.138.153   k8s-dash               root     pas@123a
10.198.138.154   k8s-ceph-dashboard     root     pas@123a
10.198.138.155   k8s-git                root     pas@123a
10.198.138.156   k8s-hub                root     pas@123a
10.198.138.158   k8s-infra              root     pas@123a
EOF
    awk '{ print $1,$2 }' "${conf_file}" >> "${dest_file}"
}

function main() {
    ssh::init
    ssh::gen_pub_key
    ssh::keep_alive

    # Config temp file path
    local conf_file="/tmp/host"
    # /etc/hosts temp file path
    local host_file="${conf_file}.host"
    make::etchosts "${conf_file}" "${host_file}"
    awk '{print $1,$2,$3,$4}' "${conf_file}" | sed  -n '3,$p' | while read -r line; do
        ip=$(echo "$line" | cut -f1 -d' ')
        host=$(echo "$line" | cut -f2 -d' ')
        user=$(echo "$line" | cut -f3 -d' ')
        pass=$(echo "$line" | cut -f4 -d' ')
        fmt::info "IP:${ip} HOST:${host} USER:${user} PWD:${pass}"
        ssh::passwordless "${ip}" "${user}" "${pass}"
        ssh::push "${ip}" "${user}" "${host_file}" /etc/hosts
        ssh::passwordless "${host}" "${user}" "${pass}"
    done
    fmt::ok "done"
}

main
