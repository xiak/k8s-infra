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

# The directory test-infra/kubernetes/install of project test-infra
# You must exec script at directory test-infra/kubernetes/install
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE}")/.." && pwd -P)"
source "${ROOT_DIR}/lib/fmt.sh"

# pkg::install ntp
function pkg::install() {
    if ! (hash ${1}) >/dev/null 2>&1; then
        fmt::info "Installing package ${1}"
        yum install -y ${1}
        fmt::ok "Done"
    fi
}

# TODO: 检查目录是否有已经下载好的文件，比较 MD5, 避免重复下载
function pkg::download() {
    local download_url=${1}
    local pkg_version=${2}
    local pkg_name=${3}
    local pkg_store_to=${4}
    local pkg_unzip_folder_name=${5}
    local bin_dir=${6}
    local download_no_check_cert=${7}
    shift 7
    local bin_names=$@

    local stored_pkg_absolute_dir="${pkg_store_to}/${pkg_name}"
    local unziped_folder_absolute_dir="${pkg_store_to}/${pkg_unzip_folder_name}"
    local cmd_param=""
    if [ "${download_no_check_cert}" == "true" ]; then
        cmd_param="--no-check-certificate"
    fi

    fmt::info "Download pkg ${pkg_name}"
    fmt::debug "Downloading from URL: ${download_url}"
    mkdir -p ${pkg_store_to}
    rm -f ${pkg_name}
    rm -f ${stored_pkg_absolute_dir}
    wget ${cmd_param} ${download_url}
    mv ${pkg_name} ${pkg_store_to}

    fmt::info "Decompression pkg ${pkg_name}"
    tar -C ${pkg_store_to} -zxvf ${stored_pkg_absolute_dir}

    fmt::info "Get binary file path: ${unziped_folder_absolute_dir}"
    for binary in ${bin_names[@]};do
        fmt::info "Copy pkg ${binary} to ${bin_dir}"
        chmod +x "${unziped_folder_absolute_dir}/${binary}"
        cp "${unziped_folder_absolute_dir}/${binary}" ${bin_dir}
    done
}