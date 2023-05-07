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

# The root of the build/dist directory

if [ "$#" -lt 1 ] || [ "${1}" == "--help" ]; then
  cat <<EOF
Create a secret in kubernetes cluster which contains self signed certificate

Usage: $(basename "$0") <secret name> <namespace>
  <secret name>         secret name
  <namespace>           kubernetes namespace

Examples:
  # create a secret which contains self signed certificate in kubernetes cluster
  $(basename "$0") gitea-cert infra

EOF
  exit 1
fi

SECRET_NAME=${1}
NAMESPACE=${2:-default}

CN="AVAMAR"
DIR="cert"

mkdir -p "${DIR}"
openssl genrsa -out "${DIR}/${SECRET_NAME}-ca-key.pem" 2048
openssl req -x509 -new -nodes -key "${DIR}/${SECRET_NAME}-ca-key.pem" -days 36500 -out "${DIR}/${SECRET_NAME}-ca.pem" -subj "/CN=${CN}"

cat > "${DIR}/${SECRET_NAME}-cert.conf" <<EOF
[ req ]
req_extensions = v3_req
distinguished_name = dn

[ dn ]

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment

[ ssl_client ]
extendedKeyUsage = clientAuth, serverAuth
basicConstraints = CA:FALSE
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

openssl genrsa -out "${DIR}/${SECRET_NAME}-key.pem" 2048 > /dev/null 2>&1
openssl req -new -key "${DIR}/${SECRET_NAME}-key.pem" -out "${DIR}/${SECRET_NAME}.csr" -subj "/CN=${SECRET_NAME}" -config "${DIR}/${SECRET_NAME}-cert.conf" > /dev/null 2>&1
openssl x509 -req -in "${DIR}/${SECRET_NAME}.csr" -CA "${DIR}/${SECRET_NAME}-ca.pem" -CAkey "${DIR}/${SECRET_NAME}-ca-key.pem" -CAcreateserial -out "${DIR}/${SECRET_NAME}.pem" -days 36500 -extensions ssl_client -extfile "${DIR}/${SECRET_NAME}-cert.conf" > /dev/null 2>&1
openssl verify -CAfile "${DIR}/${SECRET_NAME}-ca.pem" "${DIR}/${SECRET_NAME}.pem"

# Secret name (gitea-cert) must be the same as gitea.yaml
# kubectl create secret generic "${SECRET_NAME}" --from-file="${SECRET_NAME}.pem"="${DIR}/${SECRET_NAME}.pem" --from-file="${SECRET_NAME}-key.pem"="${DIR}/${SECRET_NAME}-key.pem" -n "${NAMESPACE}"
kubectl create secret tls "${SECRET_NAME}" \
  --cert="${DIR}/${SECRET_NAME}.pem" \
  --key="${DIR}/${SECRET_NAME}-key.pem" \
  -n "${NAMESPACE}"