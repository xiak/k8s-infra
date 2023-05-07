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
Create the k8s secret of the docker registry

Usage: $(basename "$0") <hub url> <hub user> <hub-password> <hub email> <k8s namespace>
  <hub url>                 registry url
  <hub user>                registry user
  <hub password>            registry password
  <hub email>               registry email
  <k8s namespace>           k8s namespace

Examples:

  $(basename "$0") hub.datadomain.com robot changeme x@xiak.com ops

EOF
  exit 1
fi

REGISTRY_URL=${1}
REGISTRY_USER=${2}
REGISTRY_PASSWORD=${3}
REGITSRY_EMAIL=${4}
K8S_NAMESPACE=${5}

kubectl create secret docker-registry hub-secret-${REGISTRY_USER} \
                    --docker-server=${REGISTRY_URL} \
                    --docker-username=${REGISTRY_USER} \
                    --docker-password=${REGISTRY_PASSWORD} \
                    --docker-email=${REGITSRY_EMAIL} \
                    -n ${K8S_NAMESPACE}