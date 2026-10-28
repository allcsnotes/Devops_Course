#!/usr/bin/env bash
# Deletes what M10-L05 created: the RDS instance, its manual snapshot and subnet group,
# the EBS volume and its snapshot, and the versioned S3 bucket(s) named allcs-media-*.
# The network from M10-L03 stays (clean it up with ../m10-l03-vpc-networking/cleanup.sh).
# Usage (in CloudShell, from this folder):  bash cleanup.sh
set -u

# 1. RDS. Lab only: --skip-final-snapshot. In production take a final snapshot instead!
#    Deleting the instance also deletes its Secrets Manager master password secret.
if aws rds describe-db-instances --db-instance-identifier allcs-db >/dev/null 2>&1; then
  aws rds delete-db-instance --db-instance-identifier allcs-db \
    --skip-final-snapshot --delete-automated-backups \
    --query "DBInstance.DBInstanceStatus" --output text
  echo "waiting for allcs-db to be deleted (several minutes)..."
  aws rds wait db-instance-deleted --db-instance-identifier allcs-db
fi
# manual snapshots survive the instance, so delete them explicitly
aws rds delete-db-snapshot --db-snapshot-identifier allcs-db-manual-1 \
  --query "DBSnapshot.Status" --output text 2>/dev/null
aws rds delete-db-subnet-group --db-subnet-group-name allcs-data 2>/dev/null

# 2. EBS: snapshot(s) of allcs-data-vol, then the volume
VOL=$(aws ec2 describe-volumes --filters Name=tag:Name,Values=allcs-data-vol \
  --query "Volumes[0].VolumeId" --output text)
if [ "$VOL" != "None" ]; then
  for s in $(aws ec2 describe-snapshots --owner-ids self --filters Name=volume-id,Values="$VOL" \
               --query "Snapshots[].SnapshotId" --output text); do
    aws ec2 delete-snapshot --snapshot-id "$s" && echo "deleted $s"
  done
  aws ec2 delete-volume --volume-id "$VOL" && echo "deleted $VOL"
fi

# 3. S3: a versioned bucket must be emptied of every version and delete marker first
for b in $(aws s3api list-buckets --query "Buckets[?starts_with(Name,'allcs-media-')].Name" --output text); do
  while true; do
    BATCH=$(aws s3api list-object-versions --bucket "$b" --max-items 500 --output json \
      --query "{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}, Quiet: \`true\`}")
    echo "$BATCH" | grep -q '"Key"' || break
    aws s3api delete-objects --bucket "$b" --delete "$BATCH" >/dev/null
  done
  aws s3api delete-bucket --bucket "$b" && echo "deleted bucket $b"
done
echo "M10-L05 resources deleted"
