#!/usr/bin/env bash
# pass.sh FROM:PATH TO:PATH - copies one file between two lab machines, the way Asha moves a CSR to the CA
# and certificates back. The file is owned by the user whose home it lands in (/home/<user>/...).
# Example: bash lab/pass.sh web01:/home/asha/tls/www.csr lab-ca:/home/asha/pki/www.csr
set -euo pipefail
src=$1 dst=$2
from=${src%%:*} fpath=${src#*:}
to=${dst%%:*}   tpath=${dst#*:}
user=$(printf '%s\n' "$tpath" | sed -n 's#^/home/\([^/]*\)/.*#\1#p')
docker exec "$from" cat "$fpath" | docker exec -i -u "${user:-root}" "$to" sh -c "cat > '$tpath'"
echo "copied $src -> $dst"
