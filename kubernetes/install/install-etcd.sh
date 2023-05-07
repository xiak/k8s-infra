#!/bin/bash

if [ "$#" -lt 7 ] || [ "${1}" == "--help" ]; then
  cat <<EOF

Description:
Install external etcd cluster

Usage: $(basename "$0") <user> <password> <version> <etcd slb domain> <etcd slb ip> <etcd cert dir> <etcd node 1> ...
  <user>                etcd node user
  <password>            etcd node password
  <version>             etcd version
  <etcd slb domain>     etcd soft load balancer domain name
  <etcd slb ip>         etcd soft load balancer ip
  <etcd work dir>       etcd work dir
  <etcd node 1>         etcd node ip
  <etcd node 2>         etcd node ip
  ...                   etcd node ip

Examples:
  $(basename "$0") root changeme 3.4.3 etcd.api.com 10.6.6.6 /etc/etcd 10.7.0.2 10.7.0.3 10.7.0.4

EOF
  exit 1
fi

source lib/fmt.sh
source lib/ssl.sh
source lib/pkg.sh
source lib/ssh.sh
source lib/service.sh
source lib/assert.sh

ETCD_USER=${1}
ETCD_PASSWORD=${2}
ETCD_VERSION=${3}
ETCD_SLB_DOMAIN=${4}
ETCD_SLB_IP=${5}
ETCD_WORK_DIR=${6}
shift 6
ETCD_NODES=$@

BIN_DIR=/usr/local/bin
SERVICE_DIR=/usr/lib/systemd/system

ETCD_DATA_DIR="${ETCD_WORK_DIR}/data"
ETCD_WAL_DIR="${ETCD_WORK_DIR}/wal"
ETCD_CERT_DIR="${ETCD_WORK_DIR}/pki"
ETCD_CA="${ETCD_CERT_DIR}/ca.pem"
ETCD_CA_KEY="${ETCD_CERT_DIR}/ca-key.pem"
ETCD_CERT="${ETCD_CERT_DIR}/etcd.pem"
ETCD_CERT_KEY="${ETCD_CERT_DIR}/etcd-key.pem"
ETCD_PKG_DIR="${ETCD_WORK_DIR}/install"
ETCD_BIN_DIR="${BIN_DIR}/etcd"
ETCDCTL_BIN_DIR="${BIN_DIR}/etcdctl"

mkdir -p ${ETCD_CERT_DIR}
mkdir -p ${ETCD_PKG_DIR}

# cfssl
#TOOL_CFSSL_VERSION=1.3.4
#TOOL_CFSSL_FILE_NAME="${TOOL_CFSSL_VERSION}.tar.gz"
#TOOL_CFSSL_FILE_FOLDER="cfssl-${TOOL_CFSSL_VERSION}/bin"
#TOOL_CFSSL_DOWNLOAD_URL="https://github.com/cloudflare/cfssl/archive/${TOOL_CFSSL_FILE_NAME}"
#TOOL_CFSSL_BIN_FILES=("cfssl" "cfssljson" "cfssl-certinfo")

# etcd
ETCD_PKG_FILE_NAME="etcd-v${ETCD_VERSION}-linux-amd64.tar.gz"
ETCD_PKG_FILE_FOLDER="etcd-v${ETCD_VERSION}-linux-amd64"
ETCD_DOWNLOAD_URL="https://github.com/coreos/etcd/releases/download/v${ETCD_VERSION}/${ETCD_PKG_FILE_NAME}"
ETCD_BIN_FILES=("etcd" "etcdctl")

ssh::init
ssh::gen_pub_key
ssh::keep_alive

# 安装 cfssl 工具
#pkg::download \
#   ${TOOL_CFSSL_DOWNLOAD_URL} \
#   ${TOOL_CFSSL_VERSION} \
#   ${TOOL_CFSSL_FILE_NAME} \
#   ${ETCD_PKG_DIR} \
#   ${TOOL_CFSSL_FILE_FOLDER} \
#   ${BIN_DIR} \
#   false \
#   "${TOOL_CFSSL_BIN_FILES[@]}"
if ! (hash cfssl) >/dev/null 2>&1; then
    fmt::fatal "Please install cfssl tool first. https://github.com/cloudflare/cfssl"
fi

pkg::download \
   ${ETCD_DOWNLOAD_URL} \
   ${ETCD_VERSION} \
   ${ETCD_PKG_FILE_NAME} \
   ${ETCD_PKG_DIR} \
   ${ETCD_PKG_FILE_FOLDER} \
   ${BIN_DIR} \
   false \
   "${ETCD_BIN_FILES[@]}"


# 生成 ca.pem 和 ca-key.pem
fmt::info "Create ca.pem and ca-key.pem"
ssl::mk::ca 87600h etcd etcd Sichuan Sichuan etcd System
# 生成 etcd.pem 和 etcd-key.pem
fmt::info "Create etcd.pem and etcd-key.pem"
ssl::mk::cert etcd etcd Sichuan Sichuan etcd System ca.pem ca-key.pem ca-config.json etcd 127.0.0.1 ${ETCD_SLB_DOMAIN} ${ETCD_SLB_IP} ${ETCD_NODES[@]}
cp {ca.pem,ca-key.pem,etcd.pem,etcd-key.pem} ${ETCD_CERT_DIR}

assert::file_existed ${ETCD_CA}
assert::file_existed ${ETCD_CA_KEY}
assert::file_existed ${ETCD_CERT}
assert::file_existed ${ETCD_CERT_KEY}

INIT_ETCD_CLUSTER_PARAM=""
ETCD_ENDPOINTS=""
for ip in ${ETCD_NODES[@]}; do
    ssh::passwordless ${ip} ${ETCD_USER} ${ETCD_PASSWORD}
    node_name=$(ssh::exec ${ip} ${ETCD_USER} "hostname")
    if [ -z ${INIT_ETCD_CLUSTER_PARAM} ]; then
        INIT_ETCD_CLUSTER_PARAM="${node_name}=https://${ip}:2380"
        ETCD_ENDPOINTS="https://${ip}:2379"
    else
        INIT_ETCD_CLUSTER_PARAM="${INIT_ETCD_CLUSTER_PARAM},${node_name}=https://${ip}:2380"
        ETCD_ENDPOINTS="${ETCD_ENDPOINTS},https://${ip}:2379"
    fi
done

fmt::info "Set parameter --initial-cluster to ${INIT_ETCD_CLUSTER_PARAM}"
fmt::info "Set etcd endpoints to ${ETCD_ENDPOINTS}"

for ip in ${ETCD_NODES[@]}; do
    ssh::exec ${ip} ${ETCD_USER} "mkdir -p ${ETCD_WORK_DIR}"
    ssh::exec ${ip} ${ETCD_USER} "mkdir -p ${ETCD_CERT_DIR}"

    fmt::info "Copy certs to ${ip}"
    # 分发证书
    ssh::push ${ip} ${ETCD_USER} "${ETCD_CA}" ${ETCD_CERT_DIR}
    ssh::push ${ip} ${ETCD_USER} "${ETCD_CA_KEY}" ${ETCD_CERT_DIR}
    ssh::push ${ip} ${ETCD_USER} "${ETCD_CERT}" ${ETCD_CERT_DIR}
    ssh::push ${ip} ${ETCD_USER} "${ETCD_CERT_KEY}" ${ETCD_CERT_DIR}

    fmt::info "Copy binary to ${ip}"
    # 分发 binary
    # 先停止旧的 etcd 服务
    ssh::exec ${ip} ${ETCD_USER} "systemctl stop etcd"
    ssh::push ${ip} ${ETCD_USER} "${ETCD_BIN_DIR}" ${BIN_DIR}
    ssh::push ${ip} ${ETCD_USER} "${ETCDCTL_BIN_DIR}" ${BIN_DIR}

    node_name=$(ssh::exec ${ip} ${ETCD_USER} "hostname")
    cat > etcd-${ip}.service <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=${ETCD_WORK_DIR}
ExecStart=${BIN_DIR}/etcd \\
  --data-dir=${ETCD_DATA_DIR} \\
  --wal-dir=${ETCD_WAL_DIR} \\
  --name=${node_name} \\
  --cert-file=${ETCD_CERT} \\
  --key-file=${ETCD_CERT_KEY} \\
  --trusted-ca-file=${ETCD_CA} \\
  --peer-cert-file=${ETCD_CERT} \\
  --peer-key-file=${ETCD_CERT_KEY} \\
  --peer-trusted-ca-file=${ETCD_CA} \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --listen-peer-urls=https://${ip}:2380 \\
  --initial-advertise-peer-urls=https://${ip}:2380 \\
  --listen-client-urls=https://${ip}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://${ip}:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${INIT_ETCD_CLUSTER_PARAM} \\
  --initial-cluster-state=new \\
  --auto-compaction-mode=periodic \\
  --auto-compaction-retention=1 \\
  --max-request-bytes=33554432 \\
  --quota-backend-bytes=6442450944 \\
  --heartbeat-interval=250 \\
  --election-timeout=2000
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    fmt::info "Copy service daemon file to ${ip}"
    # 分发 service 文件
    ssh::push ${ip} ${ETCD_USER} etcd-${ip}.service "${SERVICE_DIR}/etcd.service"

    fmt::info "Stop firewall on ${ip}"
    ssh::exec ${ip} ${ETCD_USER} "systemctl stop firewalld && systemctl disable firewalld"

    fmt::info "Start etcd service ${ip}"
    # 启动 etcd daemon 服务
    ssh::exec ${ip} ${ETCD_USER} "systemctl daemon-reload && systemctl enable etcd && systemctl restart etcd" &
done

LAST_NODE=""
for ip in ${ETCD_NODES[@]}; do
    service::remote::wait_until_active etcd ${ip} ${ETCD_USER} 10
    LAST_NODE=${ip}
done

# ETCDCTL_API=2
# cmd="ETCDCTL_API=2 etcdctl --cert-file ${ETCD_CERT} --key-file ${ETCD_CERT_KEY} --ca-file ${ETCD_CA} --endpoints https://${ETCD_SLB_IP}:2379 cluster-health"
# ssh::exec ${LAST_NODE} ${ETCD_USER} "${cmd}"
# ETCDCTL_API=3
fmt::info "Checking etcd health via https://${ETCD_SLB_IP}:2379"
cmd="ETCDCTL_API=3 etcdctl --endpoints=https://${ETCD_SLB_IP}:2379 --cacert=${ETCD_CA} --cert=${ETCD_CERT} --key=${ETCD_CERT_KEY} endpoint health"
ssh::exec ${LAST_NODE} ${ETCD_USER} "${cmd}"

fmt::info "Checking etcd health via https://${ETCD_SLB_DOMAIN}:2379"
cmd="ETCDCTL_API=3 etcdctl --endpoints=https://${ETCD_SLB_DOMAIN}:2379 --cacert=${ETCD_CA} --cert=${ETCD_CERT} --key=${ETCD_CERT_KEY} endpoint health"
ssh::exec ${LAST_NODE} ${ETCD_USER} "${cmd}"

fmt::info "Summary"
cmd="ETCDCTL_API=3 etcdctl -w table --endpoints=${ETCD_ENDPOINTS} --cacert=${ETCD_CA} --cert=${ETCD_CERT} --key=${ETCD_CERT_KEY} endpoint status"
ssh::exec ${ip} ${ETCD_USER} "${cmd}"



