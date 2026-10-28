#!/usr/bin/env bash
# Plays the part of "Priya sends Asha her public key in chat".
# Copies ONLY the public key (id_ed25519.pub) from Priya's laptop to Asha's laptop, as ~/priya.pub.
# The private key never leaves priya-laptop. Run it after Priya has made her key pair.
set -euo pipefail
docker exec priya-laptop cat /home/priya/.ssh/id_ed25519.pub \
  | docker exec -i laptop bash -c 'cat > /home/asha/priya.pub && chown asha:asha /home/asha/priya.pub'
echo "Done: Asha's laptop now has ~/priya.pub"
