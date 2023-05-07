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
Run bootstrap on the linux system before installing kubernetes

Usage: $(basename "$0") <docker registry>
  <docker registry>  Docker registry
  <ntp server 1>     ntp server
  <ntp server 2>     ntp server
  ......             ntp server

Examples:
  $(basename "$0") hub.docker.com 10.0.0.200 10.0.0.201 10.0.0.202
  $(basename "$0") you-registry.com 10.0.0.200 10.0.0.201 10.0.0.202

EOF
  exit 1
fi

source lib/fmt.sh
source lib/assert.sh
source lib/pkg.sh
source lib/ssh.sh
source lib/service.sh

DOCKER_REGISTRY=${1}
shift 1
NTP_SERVERS=$@

# if you want to upgrade repo, please un-commenting those codes
 fmt::info "Upgrade repo"
 yum update -y

# 关闭防火墙
# 暂停防火墙, 清楚规则
# docker 需要 iptable 接受转发
fmt::info "Stop and disable firewalld"
systemctl stop firewalld
systemctl disable firewalld
iptables -F && iptables -X && iptables -F -t nat && iptables -X -t nat
iptables -P FORWARD ACCEPT

# 开启 dnsmasq 后， 会将 DNS 设置为 127.0.0.1， 导致 docker 无法解析域名
fmt::info "Stop and disable dnsmasq"
systemctl stop dnsmasq
systemctl disable dnsmasq

# 必须进制挂载　swap 分区
fmt::info "Disable mount swap"
swapoff -a
sysctl -w vm.swappiness=0
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 优化内核参数
# docker 有　ipv6 bug, 建议　disable_ipv6=1
# 共用同一个NAT设备环境下，开启　tcp_tw_recycle 会导致大量 tcp 连接错误
fmt::info "Optimize kernel parameters"
cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0 # 禁止使用 swap 空间，只有当系统 OOM 时才允许使用它
vm.overcommit_memory=1 # 不检查物理内存是否够用
vm.panic_on_oom=0 # 开启 OOM
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF
sysctl -p /etc/sysctl.d/kubernetes.conf

# http 访问会出现 503, 关闭　SELinux
# k8s 挂载目录会出现　Permission denied
fmt::info "Disable SELinux"
setenforce 0
sed -i 's/^\(SELINUX=\)enforcing$/\1disabled/' /etc/selinux/config

# 关闭　NetworkManager
# IMPORTANT: 不要关闭 NetworkManager on CentOS8
#fmt::info "Stop and disable SELinux"
#systemctl stop NetworkManager
#systemctl disable NetworkManager

# 安装必要的软件包
fmt::info "Install packages"
yum install -y epel-release
yum install -y conntrack sysstat libseccomp socat ceph-common net-tools nfs-utils
pkg::install wget
pkg::install curl
pkg::install git
pkg::install openssl
pkg::install openssl-devel
pkg::install ipset
pkg::install ipvsadm
pkg::install jq
pkg::install iptables
pkg::install socat

# 加载内核模块
fmt::info "Load system mod"
modprobe br_netfilter
modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
modprobe ip_vs
# linux内核从2.6.32版本开始支持ceph
# modprobe rbd

# 设置时区
fmt::info "Set time zone"
timedatectl set-timezone Asia/Shanghai
timedatectl set-local-rtc 0
systemctl restart rsyslog
systemctl restart crond

# 设置 ntp 服务器
fmt::info "Set ntp and sync time"
yum install -y ntp
# 备份 ntp.conf 实现 cat 原子操作
if [ -e "/etc/ntp.conf.bak" ]; then
    rm -f /etc/ntp.conf
    cp /etc/ntp.conf.bak /etc/ntp.conf
else
    cp /etc/ntp.conf /etc/ntp.conf.bak
fi
sed -i 's/^\(server\)/#\1/' /etc/ntp.conf
for server in ${NTP_SERVERS[@]}; do
    cat >> /etc/ntp.conf <<EOF
server ${server}
EOF
done

# 在文件 /etc/sysconfig/ntpd 中添加 SYNC_HWCLOCK=yes, 以便同步硬件时钟
cat > /etc/sysconfig/ntpd <<EOF
OPTIONS="-g"
SYNC_HWCLOCK=yes
EOF
cat /etc/sysconfig/ntpd

# User chronyd on centos8
# systemctl stop chronyd
# systemctl disable chronyd
systemctl enable ntpd
systemctl restart ntpd
systemctl restart rsyslog
systemctl restart crond

# 信任证书
# 把需要信任的证书添加到这里
fmt::info "CA trust"
fmt::process "gcr.io:443"
echo -n | openssl s_client -showcerts -connect cloud.google.com:443 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >> /etc/pki/ca-trust/source/anchors/gcrio.crt
fmt::ok "done"
echo -n | openssl s_client -showcerts -connect gcr.io:443 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >> /etc/pki/ca-trust/source/anchors/gcr.io.crt
fmt::ok "done"
fmt::process "quay.io:443"
echo -n | openssl s_client -showcerts -connect quay.io:443 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >> /etc/pki/ca-trust/source/anchors/quayio.crt
fmt::ok "done"
fmt::process "googleapis.com:443"
echo -n | openssl s_client -showcerts -connect storage.googleapis.com:443 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >> /etc/pki/ca-trust/source/anchors/googleapis.crt
fmt::ok "done"
update-ca-trust extract
if (hash docker) >/dev/null 2>&1; then
    systemctl restart docker
fi

# 添加或更新 docker daemon 配置文件
# 设置 docker registry 地址
# 设置 driver 用 systemd 替代 cgroup
# 设置 logger
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "insecure-registries": ["${DOCKER_REGISTRY}"],
  "max-concurrent-downloads": 10,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
mkdir -p /etc/systemd/system/docker.service.d
if (hash docker) >/dev/null 2>&1; then
    # systemctl reload docker
    systemctl restart docker
fi

fmt::info "bootstrap.sh: All tasks have been done"

