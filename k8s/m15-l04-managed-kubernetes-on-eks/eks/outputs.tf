output "cluster_name" { value = aws_eks_cluster.main.name }
output "cluster_version" { value = aws_eks_cluster.main.version }
output "oidc_issuer" { value = aws_eks_cluster.main.identity[0].oidc[0].issuer }
output "media_bucket" { value = aws_s3_bucket.media.bucket }
output "media_reader_role_arn" { value = aws_iam_role.media_reader.arn }
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region us-east-1"
}
