#!/bin/bash

# Copyright 2020 Dell EMC - Avamar MC Authors
#
# Maintainer: drizzt.xia@dell.com
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

# TODO: install tool management: yum, apk add
# TODO: service management for different OS, such as rc-service, service, systemctl

# The directory test-infra/kubernetes/install of project test-infra
# You must exec script at directory test-infra/kubernetes/install
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE}")/.." && pwd -P)"

source "${ROOT_DIR}/lib/fmt.sh"

# Preflight check
# Install expect, openssl, ssh-copy-id
function ssh::init() {
    fmt::info "Init ssh client"
    ssh::install_expect
    ssh::install_openssh
    fmt::ok "ssh client has already to serve"
}

# install expect
function ssh::install_expect() {
  if ! (hash expect) >/dev/null 2>&1; then
      if (hash yum) >/dev/null 2>&1; then
          # centos, redhat
          yum install -y expect
      elif (hash apk) >/dev/null 2>&1; then
          # alpine
          apk add --update --upgrade && apk add expect
      else
          # ubuntu
          apt-get -qqy update && apt-get -qqy install expect
      fi
  fi
}

# install openssl
function ssh::install_openssh() {
  if ! (hash ssh) >/dev/null 2>&1 || ! (hash ssh-keygen) >/dev/null 2>&1 || ! (hash ssh-copy-id) >/dev/null 2>&1; then
      if (hash yum) >/dev/null 2>&1; then
          # centos, redhat
          yum install -y openssh
      elif (hash apk) >/dev/null 2>&1; then
          # alpine
          apk add --update --upgrade && apk add openssh
      else
          # ubuntu
          apt-get -qqy update && apt-get -qqy install openssh
      fi
  fi
}

# generate public key
function ssh::gen_pub_key() {
    # Check old id_rsa
    fmt::info "Check ssh pub key file ......"
    stat ~/.ssh/id_rsa >/dev/null 2>&1 && stat ~/.ssh/id_rsa.pub > /dev/null 2>&1
    if [ $? != 0 ]; then
        fmt::process "Can't found pub key, gen new one"
        rm -f ~/.ssh/id_rsa
        rm -f ~/.ssh/id_rsa.pub
        # Generate new id_rsa.pub
        expect -c "
            set timeout -1;
            spawn ssh-keygen -t rsa;
            expect {
                */root/.ssh/id_rsa* {send -- \r;exp_continue;}
                *passphrase):*      {send -- \r;exp_continue;}
                *again:*            {send -- \r;exp_continue;}
                eof                 {exit 0;}
        }" > /dev/null 2>&1;
        fmt::ok "Done"
    else
        fmt::ok "Public key has already exists"
    fi

}

# keep alive with ssh server
function ssh::keep_alive() {
    # Send a package to the server every 30 seconds to keep session alive
    # Disconnect from server when no response from server (60 times)
    fmt::info "Set ssh keepalive"
    cat >  ~/.ssh/config <<EOF
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 60
EOF
    # cat ~/.ssh/config
    # Restart sshd service
    if (hash systemctl) >/dev/null 2>&1; then
        systemctl restart sshd
    elif (hash rc-service) >/dev/null 2>&1; then
        rc-service sshd restart
    else
        service sshd restart
    fi
    fmt::ok "Client will send package to server every 30 seconds and will disconnect from server if no response from server 60 times"
}

# passwordless of remote server
# usage: ssh::passwordless "192.169.1.2" "admin" "password"
function ssh::passwordless() {
    local host="$1"
    local user="$2"
    local pwd="$3"
    fmt::process "Set up passwordless ssh conncetion for $user@$host"
    # Remove old record from ~/.ssh/known_hosts
    # spawn ssh-copy-id -o StrictHostKeyChecking=no $user@$host;
    ssh-keygen -R $host >/dev/null 2>&1
    expect <<EOF > /dev/null
set timeout 60
spawn ssh-copy-id $user@$host;
expect {
    "yes/no"                     { send "yes\r"; exp_continue }
    "*assword*"                  { send "$pwd\r"; exp_continue }
    "No route to host"           { exit 1 }
    "Could not resolve hostname" { exit 1 }
    "*ermission denied*"         { exit 2 }
    "Connection refused"         { exit 2 }
    timeout                      { exit 3 }
    eof                          { exit 0 }
}
EOF
    local code=$?
    if [ "${code}" != "0" ]; then
        fmt::fail "fail: ${code} (1-No route to host, 2-Permission denied/refused, 3-Time out)"
        return ${code}
    fi
    fmt::ok "success"
}

# exec command on remote server
# usage: ssh::exec "192.168.1.2" "admin" "ls -l"
function ssh::exec() {
    local host="$1"
    local user="$2"
    shift 2
    local cmd=$@
    ssh $user@$host $cmd
    if [ $? != 0 ]; then
        fmt::fail "fail"
        return 1
    fi
}

# push a file from local to remote server
# usage: ssh::push "192.168.1.2" "admin" "/file/path/on/localhost" "/file/path/on/remote/server"
function ssh::push() {
    local host="$1"
    local user="$2"
    local src="$3"
    local target="$4"
    fmt::process "copy $src to $user@$host:$target"
    scp -r $src $user@$host:$target >/dev/null 2>&1
    if [ $? != 0 ]; then
        fmt::error "push fail"
    fi
    fmt::ok "success"
}

function ssh::pull() {
    local host=${1}
    local user=${2}
    local target=${3}
    local src=${4}

    fmt::process "copy $user@$host:$target to $src"
    scp -r $user@$host:$target $src >/dev/null 2>&1
    if [ $? != 0 ]; then
        fmt::error "ssh::pull fail"
        return 1
    fi
    fmt::ok "success"
}

function ssh::check_dir_exist() {
    local host=$1
    local user=$2
    local dir=$3

    fmt::info "Check dir ${user}@${host}:${dir} if it is existed"
    ssh $user@$host "if [ -d ${dir} ]; then exit 0; else exit 1; fi"
    if [ $? == 0 ]; then
        fmt::ok "the dir ${dir} is existed"
    else
        fmt::ok "the dir ${dir} is not existed"
    fi
}
