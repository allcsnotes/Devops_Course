apiVersion: v1
kind: ServiceAccount
metadata:
  name: media-reader
  namespace: allcsvideos
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
---
apiVersion: v1
kind: Pod
metadata:
  name: s3-reader
  namespace: allcsvideos
spec:
  serviceAccountName: media-reader
  restartPolicy: Never
  containers:
    - name: aws
      image: public.ecr.aws/aws-cli/aws-cli:2.38.1
      command: ["sh", "-c"]
      args:
        - |
          aws sts get-caller-identity --query Arn --output text
          aws s3 ls s3://${BUCKET} --recursive
          aws s3 ls 2>&1 | tail -1
---
apiVersion: v1
kind: Pod
metadata:
  name: no-irsa
  namespace: allcsvideos
spec:
  restartPolicy: Never
  containers:
    - name: aws
      image: public.ecr.aws/aws-cli/aws-cli:2.38.1
      command: ["sh", "-c", "aws s3 ls s3://${BUCKET} 2>&1 | tail -2"]
