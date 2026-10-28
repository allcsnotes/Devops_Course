# Self-managed worker node: our own Auto Scaling group joins the cluster.
# (This sandbox allows neither managed node groups nor Fargate profiles.)
data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/${var.kubernetes_version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

resource "aws_iam_role" "node" {
  name               = "AmazonEKSNodeRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
}

resource "aws_iam_instance_profile" "node" {
  name = "AmazonEKSNodeRole"
  role = aws_iam_role.node.name
}

# Lets instances with the node role register as Kubernetes nodes.
resource "aws_eks_access_entry" "node" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
}

locals {
  node_config = <<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="BOUNDARY"

    --BOUNDARY
    Content-Type: application/node.eks.aws

    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      cluster:
        name: ${aws_eks_cluster.main.name}
        apiServerEndpoint: ${aws_eks_cluster.main.endpoint}
        certificateAuthority: ${aws_eks_cluster.main.certificate_authority[0].data}
        cidr: ${aws_eks_cluster.main.kubernetes_network_config[0].service_ipv4_cidr}

    --BOUNDARY--
  EOT
}

resource "aws_launch_template" "node" {
  name_prefix            = "${var.cluster_name}-node-"
  image_id               = data.aws_ssm_parameter.eks_ami.insecure_value
  instance_type          = var.node_instance_type
  user_data              = base64encode(local.node_config)
  vpc_security_group_ids = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.node.name
  }

  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.cluster_name}-node" }
  }
}

resource "aws_autoscaling_group" "nodes" {
  name                = "${var.cluster_name}-nodes"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = module.vpc.private_subnets

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  depends_on = [aws_eks_access_entry.node, aws_iam_role_policy_attachment.node]
}
