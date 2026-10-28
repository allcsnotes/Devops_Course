#!/bin/bash
# Container start: run nginx (master as root, workers as www-data), then open a login shell as asha.
nginx
exec su - asha
