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

if [ "$#" -lt 1 ] || [ "${1}" == "--help" ]; then
  cat <<EOF

Description:
Install ceph cluster

Usage: $(basename "$0") <cluster name>
  <release>         ceph release name

Examples:

EOF
  exit 1
fi

RELEASE=${1}

source lib/fmt.sh
source lib/ssh.sh

fmt::info "Check python3"
if ! (hash python3) >/dev/null 2>&1; then
    yum install -y python3
fi

# 安装包
fmt::info "Check cephadm"
if (hash cephadm) >/dev/null 2>&1; then
    curl --silent --remote-name --location https://github.com/ceph/ceph/raw/octopus/src/cephadm/cephadm
    chmod +x cephadm
    cp cephadm /usr/local/bin
fi

fmt::info "Install ceph-common"
cephadm add-repo --release ${RELEASE}
cephadm install ceph-common

user=ceph
if id -u $user >/dev/null 2>&1; then
    fmt::info "User ${user} has already existed"
else
    fmt::info "Create user ${user}"
    sudo useradd -d /home/ceph -m ceph
    passwd ceph
    sudo echo "ceph ALL = (root) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ceph
    sudo chmod 0440 /etc/sudoers.d/ceph
fi

fmt::info "Install ceph"
cat > /etc/yum.repos.d/ceph.repo <<EOF
[Ceph]
name=Ceph x86_64
baseurl=https://download.ceph.com/rpm-$RELEASE/el8/x86_64
enabled=1
gpgcheck=1
gpgkey=https://download.ceph.com/keys/release.asc

[Ceph-noarch]
name=Ceph noarch
baseurl=https://download.ceph.com/rpm-$RELEASE/el8/noarch
enabled=1
gpgcheck=1
gpgkey=https://download.ceph.com/keys/release.asc

[Ceph-source]
name=Ceph SRPMS
baseurl=https://download.ceph.com/rpm-$RELEASE/el8/SRPMS
enabled=1
gpgcheck=1
gpgkey=https://download.ceph.com/keys/release.asc
EOF
yum install -y ceph

fmt::info "Start mon"
# 新建工作目录
mkdir -p /etc/ceph
mkdir -p /var/lib/ceph/bootstrap-osd

# 生成 fsid
fmt::process "Generate fsid:"
fsid=$(uuidgen)
fmt::ok "${fsid}"

# 生成配置文件 etc/ceph/ceph.conf, 注意, ceph.conf 中 ceph 为集群名。你可以定义为其他的，如 prod.conf, dev.conf
config_file="/etc/ceph/ceph.conf"
fmt::process "Generate ${config_file}"
cat > "${config_file}" <<EOF
[global]
fsid = $fsid
mon_initial_members = k8s-ceph-1,k8s-ceph-2,k8s-ceph-3
mon_host = 10.98.151.55,10.98.151.56,10.98.151.65
public_network = 10.98.151.0/24
auth_cluster_required = cephx
auth_service_required = cephx
auth_client_required = cephx
EOF
fmt::ok "done"

ceph_install_workspace=/xiak/ceph/install

mkdir -p "${ceph_install_workspace}"

fmt::info "Generate mon key"
sudo ceph-authtool --create-keyring ${ceph_install_workspace}/ceph.mon.keyring --gen-key -n mon. --cap mon 'allow *'

fmt::info "Generate admin client key"
sudo ceph-authtool --create-keyring /etc/ceph/ceph.client.admin.keyring --gen-key -n client.admin --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'

fmt::info "Generate osd bootstrap client key"
sudo ceph-authtool --create-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring --gen-key -n client.bootstrap-osd --cap mon 'profile bootstrap-osd' --cap mgr 'allow r'

# create mon keyring
sudo ceph-authtool ${ceph_install_workspace}/ceph.mon.keyring --import-keyring /etc/ceph/ceph.client.admin.keyring
sudo ceph-authtool ${ceph_install_workspace}/ceph.mon.keyring --import-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring
sudo chown ceph:ceph ${ceph_install_workspace}/ceph.mon.keyring

# create init mon map
fmt::info "Init mon map"
monmaptool --create --add k8s-ceph-1 10.98.151.55 --add k8s-ceph-2 10.98.151.56 --add k8s-ceph-3 10.98.151.65 --fsid "${fsid}" --clobber ${ceph_install_workspace}/monmap

# Add mon k8s-ceph-1
# {cluster-name}-{hostname}
fmt::info "Add mon k8s-ceph-1"
sudo -u ceph rm -rf /var/lib/ceph/mon/ceph-k8s-ceph-1
sudo -u ceph mkdir -p /var/lib/ceph/mon/ceph-k8s-ceph-1
sudo -u ceph ceph-mon --cluster ceph --mkfs -i k8s-ceph-1 --monmap ${ceph_install_workspace}/monmap --keyring ${ceph_install_workspace}/ceph.mon.keyring

#fmt::info "Start mon k8s-ceph-1 "
#systemctl daemon-reload
#systemctl start ceph-mon@k8s-ceph-1
#
#fmt::info "Get mon status"
#systemctl status -l ceph-mon@k8s-ceph-1

systemctl enable --now ceph-mon@.service


