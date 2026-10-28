variable "region" {
  type    = string
  default = "us-east-1"
}

variable "env" {
  type    = string
  default = "prod"
}

variable "app_image" {
  type    = string
  default = "public.ecr.aws/nginx/nginx:1.29-alpine"
}

variable "desired_tasks" {
  type    = number
  default = 2
}

variable "node_type" {
  type    = string
  default = "t3.mirco"
}
