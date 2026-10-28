#!/usr/bin/env bash
# login.sh: read a name, and a secret without echoing it
read -p "Your name: " name
read -s -p "Demo password (fake): " pass
echo
echo "Hello, $name. Your password has ${#pass} characters."
