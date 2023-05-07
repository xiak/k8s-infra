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

# 对象不能为空
function assert::obj_not_null() {
    if [ ! ${1} ]; then
        fmt::fatal "Input object is null, please check"
    fi
}
# 文件必须存在
function assert::file_existed() {
    if [ ! -f ${1} ]; then
        fmt::fatal "Input file ${1} is not existed, please check"
    fi
}

function assert::path_existed() {
    if [ ! -d ${1} ]; then
        fmt::fatal "Input path ${1} is not existed, please check"
    fi
}

function assert::path_not_existed() {
    if [ -d ${1} ]; then
        fmt::fatal "Input path ${1} is still existed, please check"
    fi
}