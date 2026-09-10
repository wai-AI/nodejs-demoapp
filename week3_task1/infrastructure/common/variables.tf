variable "aws_region" {
  description = "AWS region"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "Use a standard AWS region such as eu-central-1."
  }
}

variable "environment" {
  description = "dev / production"
  type        = string

  validation {
    condition     = contains(["dev", "production"], var.environment)
    error_message = "environment must be dev or production."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs for the ALB and NAT gateways"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "Private subnet CIDRs for the EC2 Auto Scaling group"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "EC2 host port used by the target group and Docker port publishing"
  type        = number
  default     = 3000

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535 && floor(var.app_port) == var.app_port
    error_message = "app_port must be an integer from 1 to 65535."
  }
}

variable "health_check_path" {
  description = "Route for health check of Target Group"
  type        = string
  default     = "/healthz"

  validation {
    condition     = can(regex("^/[A-Za-z0-9/_-]*$", var.health_check_path))
    error_message = "Use a simple absolute HTTP health-check path."
  }
}

variable "asg_min_size" {
  description = "Min EC2"
  type        = number

  validation {
    condition     = var.asg_min_size >= 1 && floor(var.asg_min_size) == var.asg_min_size
    error_message = "asg_min_size must be a positive integer."
  }
}

variable "asg_max_size" {
  description = "Max EC2"
  type        = number

  validation {
    condition     = var.asg_max_size >= 1 && floor(var.asg_max_size) == var.asg_max_size
    error_message = "asg_max_size must be a positive integer."
  }
}

variable "asg_desired_capacity" {
  description = "Desired EC2"
  type        = number

  validation {
    condition     = var.asg_desired_capacity >= 1 && floor(var.asg_desired_capacity) == var.asg_desired_capacity
    error_message = "asg_desired_capacity must be a positive integer."
  }
}

variable "alert_email" {
  description = "Email for SNS"
  type        = string
}

variable "docker_image" {
  description = "Private ECR image URI in aws_region; build linux/amd64 and deploy an immutable digest"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9][a-z0-9/_.-]*(:[A-Za-z0-9_][A-Za-z0-9_.-]*|@sha256:[a-f0-9]{64})$", var.docker_image))
    error_message = "Use a private ECR image URI with an explicit tag or sha256 digest."
  }
}

variable "key_name" {
  description = "Key SSH"
  type        = string
  default     = null
}

variable "ssh_allowed_cidr" {
  description = "CIDR for SSH connect"
  type        = string
  default     = null
}

variable "container_port" {
  description = "Node PORT inside the container; independent from the EC2 host port"
  type        = number
  default     = 3000

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer from 1 to 65535."
  }
}
