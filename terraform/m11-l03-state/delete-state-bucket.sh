#!/usr/bin/env bash
# Deletes the Terraform state bucket from M11-L03, including every object version
# (state versions and old .tflock files). Run it LAST, after `terraform destroy`
# of every project that keeps its state in this bucket (hello in lessons 3 and 6).
# Usage:  bash delete-state-bucket.sh [bucket-name]     (default: the name in ~/state_bucket)
set -eu
B=${1:-$(cat ~/state_bucket)}
echo "emptying and deleting s3://$B"
while true; do
  BATCH=$(aws s3api list-object-versions --bucket "$B" --max-items 500 --output json \
    --query "{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}, Quiet: \`true\`}")
  echo "$BATCH" | grep -q '"Key"' || break
  aws s3api delete-objects --bucket "$B" --delete "$BATCH" >/dev/null
done
aws s3api delete-bucket --bucket "$B" && echo "deleted $B"
rm -f ~/state_bucket
