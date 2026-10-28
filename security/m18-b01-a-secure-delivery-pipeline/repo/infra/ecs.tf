data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

# Instance profile created by hand in Module 10 (the playground only lets us
# create IAM roles with this name), so we look it up instead of creating it.
data "aws_iam_instance_profile" "ecs" {
  name = "ecsInstanceRole"
}

resource "aws_ecs_cluster" "main" {
  name = "allcs-${var.env}"
}

resource "aws_launch_template" "ecs" {
  name_prefix            = "allcs-${var.env}-ecs-"
  image_id               = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ecs_nodes.id]
  iam_instance_profile { name = data.aws_iam_instance_profile.ecs.name }
  metadata_options { http_tokens = "required" }
  user_data = base64encode("#!/bin/bash\necho ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config\n")
}

resource "aws_autoscaling_group" "ecs" {
  name                = "allcs-${var.env}-ecs"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = module.vpc.private_subnets
  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "allcs-${var.env}-ecs-node"
    propagate_at_launch = true
  }
}

resource "aws_ecs_task_definition" "web" {
  family                   = "allcs-${var.env}-web"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  container_definitions = jsonencode([{
    name         = "web"
    image        = var.app_image
    memory       = 128
    cpu          = 128
    essential    = true
    portMappings = [{ containerPort = 80, hostPort = 0 }]
  }])
}

resource "aws_ecs_service" "web" {
  name            = "web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = var.desired_tasks
  launch_type     = "EC2"
  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.http]
}
