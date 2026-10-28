#!/bin/bash
# Lab certificates, made with openssl inside proxy-01 (fake lab CA, never trusted outside this lab):
#   ca.crt            "allcsvideos Lab CA", 10 years
#   good.crt          allcsvideos.test + www.allcsvideos.test, 90 days from today
#   expired.crt       same names, 90 days that ended yesterday (STAGED)
#   staging.crt       staging.allcsvideos.test only (STAGED mismatch)
set -euo pipefail
mkdir -p /root/ca && cd /root/ca
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 3650 -subj "/O=allcsvideos lab/CN=allcsvideos Lab CA" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout site.key -out site.csr -subj "/CN=allcsvideos.test" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout staging.key -out staging.csr -subj "/CN=staging.allcsvideos.test" 2>/dev/null
mkdir -p db && : > db/index.txt && echo 1000 > db/serial
cat > ca.cnf <<'CNF'
[ca]
default_ca = lab
[lab]
dir = /root/ca
database = $dir/db/index.txt
serial = $dir/db/serial
new_certs_dir = $dir/db
certificate = $dir/ca.crt
private_key = $dir/ca.key
default_md = sha256
policy = any
copy_extensions = none
unique_subject = no
[any]
commonName = supplied
[site]
subjectAltName = DNS:allcsvideos.test,DNS:www.allcsvideos.test
basicConstraints = CA:FALSE
extendedKeyUsage = serverAuth
[staging]
subjectAltName = DNS:staging.allcsvideos.test
basicConstraints = CA:FALSE
extendedKeyUsage = serverAuth
CNF
TODAY=$(date -u +%Y%m%d)
openssl ca -batch -config ca.cnf -extensions site -in site.csr -out good.crt -startdate ${TODAY}000000Z -days 90 -notext 2>/dev/null
openssl ca -batch -config ca.cnf -extensions site -in site.csr -out expired.crt \
  -startdate $(date -u -d "-91 days" +%Y%m%d)120000Z -enddate $(date -u -d "-1 day" +%Y%m%d)120000Z -notext 2>/dev/null
openssl ca -batch -config ca.cnf -extensions staging -in staging.csr -out staging.crt -startdate ${TODAY}000000Z -days 90 -notext 2>/dev/null
ls /root/ca/*.crt
