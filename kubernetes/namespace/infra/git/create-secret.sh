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

# kubectl get secret -n infra
SECRET_NAME="gitea-cert"
NAMESPACE="infra"

# delete old secret
kubectl delete secret "${SECRET_NAME}" -n "${NAMESPACE}"

# create a new one
./make-cert.sh "${SECRET_NAME}" "${NAMESPACE}"

# secret show
kubectl describe secret "${SECRET_NAME}" -n "${NAMESPACE}"