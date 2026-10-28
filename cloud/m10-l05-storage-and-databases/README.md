# M10-L05 · Storage and Databases
> Video: Module 10, Lesson 5. Watch it first, then follow along here.

## What you'll learn
- The three storage shapes: **object** (S3), **block** (EBS), **file** (EFS), plus the managed database **RDS**
- S3 basics: buckets, keys and prefixes (no real folders), global bucket names, Block Public Access and encryption on by default
- **Versioning** as the undo button, and a **lifecycle rule** to tidy old versions
- EBS volumes live in **one AZ**; snapshots live in the region and are how you move or protect a disk
- RDS PostgreSQL in isolated subnets with a password **managed in Secrets Manager** (nobody types it)
- Backups vs availability: automated backups and point-in-time recovery, manual snapshots, Multi-AZ, read replicas, RPO and RTO

## Before you start
- AWS CloudShell in **us-east-1** with this repo cloned.
- The network from [M10-L03](../m10-l03-vpc-networking/) must exist (the RDS part uses `data-a`, `data-b` and the `allcs-db` security group). Reload variables if needed:
  ```bash
  cd Devops_Course/cloud/m10-l03-vpc-networking && source helpers.sh && source find-ids.sh && cd ../m10-l05-storage-and-databases
  ```
- You do **not** need lesson 4's servers running.

> **Cost warning** (approx. us-east-1, check the S3, EBS and RDS pricing pages):
> - S3: a few tiny objects, effectively free
> - EBS: 8 GiB gp3 about US$0.08 per GiB-month (cents for a day); its snapshot about US$0.05 per GiB-month
> - RDS `db.t3.micro` about **US$0.018/hour** plus 20 GiB gp3 storage (~US$0.115 per GiB-month)
> - the RDS-managed secret in Secrets Manager about US$0.40/month, prorated
> - plus the NAT gateway from lesson 3 if it is still running
>
> The database is the expensive part. Run the [Clean up](#clean-up) when you finish.

## Files in this folder
| File | What it is |
|---|---|
| `lifecycle.json` | the `old-versions` lifecycle rule from the video (noncurrent versions: STANDARD_IA after 30 days, deleted after 90) |
| `cleanup.sh` | deletes the RDS instance and snapshot, subnet group, EBS volume and snapshot, and empties and deletes the bucket |

## Follow along

### S3
1. Create a bucket with a unique name (bucket names are global across all AWS accounts):
   ```bash
   MEDIA=allcs-media-$RANDOM$RANDOM; aws s3api create-bucket --bucket $MEDIA --query Location --output text
   aws s3api get-public-access-block --bucket $MEDIA --output table
   ```
   You should see `/allcs-media-<numbers>` and all four Block Public Access settings `True` (on by default since April 2023).

2. Upload an object under a prefix and list it:
   ```bash
   echo "Lesson 1 notes" > notes.txt; aws s3 cp notes.txt s3://$MEDIA/lessons/l01/notes.txt
   aws s3 ls s3://$MEDIA --recursive
   ```
   `15 lessons/l01/notes.txt` (14 characters + newline).

3. Turn on versioning, overwrite the file, and list the versions:
   ```bash
   aws s3api put-bucket-versioning --bucket $MEDIA --versioning-configuration Status=Enabled; aws s3api get-bucket-versioning --bucket $MEDIA
   echo "Lesson 1 notes v2" > notes.txt; aws s3 cp notes.txt s3://$MEDIA/lessons/l01/notes.txt >/dev/null; aws s3api list-object-versions --bucket $MEDIA --prefix lessons/l01/notes.txt --query "Versions[].[VersionId,IsLatest,Size]" --output table
   ```
   You should see:
   ```
   |  p_y8TuxGfoqFFOyEoM2CGwkiVqz_82GA |  True  |  18  |
   |  null                             |  False |  15  |
   ```
   The old version is kept (`null` because it was uploaded before versioning). Every version is billed as a full object.

4. Add the lifecycle rule (the video passed the same JSON inline) and check encryption:
   ```bash
   cat lifecycle.json
   aws s3api put-bucket-lifecycle-configuration --bucket $MEDIA --lifecycle-configuration file://lifecycle.json && aws s3api get-bucket-lifecycle-configuration --bucket $MEDIA
   aws s3api get-bucket-encryption --bucket $MEDIA --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault"
   ```
   The rule comes back with an extra `"TransitionDefaultMinimumObjectSize": "all_storage_classes_128K"` (objects under 128 KB don't transition). Encryption shows `"SSEAlgorithm": "AES256"` (SSE-S3, on for every new upload since January 2023).

### EBS
5. Create an 8 GiB gp3 volume in `us-east-1a` (**billed per GiB-month while it exists**). This uses the `tg` helper from lesson 3:
   ```bash
   VOL=$(aws ec2 create-volume --availability-zone us-east-1a --size 8 --volume-type gp3 --tag-specifications "$(tg volume allcs-data-vol)" --query VolumeId --output text); aws ec2 wait volume-available --volume-ids $VOL; aws ec2 describe-volumes --volume-ids $VOL --query "Volumes[0].[VolumeId,Size,VolumeType,Iops,Throughput,AvailabilityZone,State]" --output table
   ```
   `8 | gp3 | 3000 | 125 | us-east-1a | available`: the gp3 baseline is 3,000 IOPS and 125 MiB/s at any size. Only an instance in `us-east-1a` could attach it.

6. Snapshot it:
   ```bash
   SNAP=$(aws ec2 create-snapshot --volume-id $VOL --description "allcs-data before upgrade" --query SnapshotId --output text); echo $SNAP; time aws ec2 wait snapshot-completed --snapshot-ids $SNAP; aws ec2 describe-snapshots --snapshot-ids $SNAP --query "Snapshots[0].[SnapshotId,State,VolumeSize,StartTime]" --output table
   ```
   46 seconds in the video, state `completed`. AWS does **not** back up EBS volumes for you: schedule snapshots (Data Lifecycle Manager or AWS Backup).

### RDS
7. A DB subnet group from the two isolated data subnets (free):
   ```bash
   aws rds create-db-subnet-group --db-subnet-group-name allcs-data --db-subnet-group-description "data subnets" --subnet-ids $DATAA $DATAB --query "DBSubnetGroup.Subnets[].[SubnetIdentifier,SubnetAvailabilityZone.Name]" --output table
   ```

8. Pick the newest PostgreSQL 17 minor version (sort as versions, `sort -V`, not as text):
   ```bash
   aws rds describe-orderable-db-instance-options --engine postgres --db-instance-class db.t3.micro --query "OrderableDBInstanceOptions[].EngineVersion" --output text | tr "\t" "\n" | grep "^17\." | sort -uV | tail -3
   PGV=$(aws rds describe-orderable-db-instance-options --engine postgres --db-instance-class db.t3.micro --query "OrderableDBInstanceOptions[].EngineVersion" --output text | tr "\t" "\n" | grep "^17\." | sort -uV | tail -1); echo $PGV
   ```
   The video got `17.9 17.10 17.11` and used `17.11`. Yours may be newer.

9. Create the database (**starts billing**, ~US$0.018/h + storage). No password anywhere: `--manage-master-user-password` makes RDS generate it and keep it in Secrets Manager. `--no-multi-az` keeps the lab cheap; production turns Multi-AZ on.
   ```bash
   aws rds create-db-instance --db-instance-identifier allcs-db --engine postgres --engine-version $PGV --db-instance-class db.t3.micro --allocated-storage 20 --storage-type gp3 --master-username allcs --manage-master-user-password --db-subnet-group-name allcs-data --vpc-security-group-ids $SGDB --no-publicly-accessible --backup-retention-period 1 --no-multi-az --storage-encrypted --query "DBInstance.[DBInstanceIdentifier,Engine,EngineVersion,DBInstanceClass,DBInstanceStatus]" --output table
   time aws rds wait db-instance-available --db-instance-identifier allcs-db
   ```
   Status `creating`, then the wait took `6m3s` in the video.

10. Check it, its secret, and take a manual snapshot (**billed per GiB-month until deleted**):
    ```bash
    aws rds describe-db-instances --db-instance-identifier allcs-db --query "DBInstances[0].[DBInstanceStatus,Endpoint.Address,Endpoint.Port,PubliclyAccessible,StorageEncrypted,BackupRetentionPeriod,MultiAZ]" --output table
    aws rds describe-db-instances --db-instance-identifier allcs-db --query "DBInstances[0].MasterUserSecret.SecretStatus" --output text
    aws rds create-db-snapshot --db-instance-identifier allcs-db --db-snapshot-identifier allcs-db-manual-1 --query "DBSnapshot.[DBSnapshotIdentifier,Status,SnapshotType]" --output text
    ```
    You should see `available`, an endpoint like `allcs-db.<random>.us-east-1.rds.amazonaws.com`, `5432`, `False` (not public), `True` (encrypted), `1` (backup days), `False` (Multi-AZ); then `active`; then `allcs-db-manual-1 creating manual`.

## Key ideas: backups vs availability
| Feature | Protects against | Notes |
|---|---|---|
| Automated backups | data loss, mistakes | daily snapshot + logs every 5 min, 0-35 days; point-in-time restore creates a **new** instance/endpoint |
| Manual snapshot | risky changes | kept until you delete it, even after the instance is gone |
| Multi-AZ | zone/instance failure | synchronous standby, automatic failover in ~60-120 s, same DNS name |
| Read replica | too many reads | asynchronous, read-only, can lag |

A standby or replica is **not** a backup: `DROP TABLE` is copied to them in moments. RPO = how much data you may lose; RTO = how long you may be down. Prove both with a restore drill.

## Common mistakes
- Public buckets: keep Block Public Access on; share single objects with presigned URLs.
- State on instance disks: uploads saved on a web server vanish when the Auto Scaling group replaces it.
- A single-AZ database in production: turn on Multi-AZ.
- No restore test: a backup you never restored is a hope.
- Hard-coded database passwords (code, `.env`, Terraform variables): let RDS manage it in Secrets Manager.
- Deleting a database without a final snapshot in production: take one and turn on deletion protection. (The lab clean up below skips it on purpose.)

## Clean up
```bash
bash cleanup.sh
```
It runs, in order:
- `aws rds delete-db-instance --db-instance-identifier allcs-db --skip-final-snapshot --delete-automated-backups` + `aws rds wait db-instance-deleted` (lab only; this also deletes the managed secret)
- `aws rds delete-db-snapshot --db-snapshot-identifier allcs-db-manual-1` and `aws rds delete-db-subnet-group --db-subnet-group-name allcs-data`
- `aws ec2 delete-snapshot` for the volume's snapshots, then `aws ec2 delete-volume`
- deletes every object version and delete marker in each `allcs-media-*` bucket, then `aws s3api delete-bucket`

The network from lesson 3 is still there. Lesson 6 uses it; if you stop here, run `bash ../m10-l03-vpc-networking/cleanup.sh`.

## Next
[M10-L06 · Serverless and Managed Containers](../m10-l06-serverless-and-managed-containers/)
