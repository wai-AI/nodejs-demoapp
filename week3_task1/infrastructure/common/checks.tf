resource "terraform_data" "configuration" {
  lifecycle {
    precondition {
      condition     = var.asg_min_size <= var.asg_desired_capacity && var.asg_desired_capacity <= var.asg_max_size
      error_message = "ASG capacity must satisfy min <= desired <= max."
    }
    precondition {
      condition     = length(distinct(var.azs)) >= 2 && length(var.public_subnets) == length(var.azs) && length(var.private_subnets) == length(var.azs)
      error_message = "Provide at least two distinct AZs and one public/private subnet per AZ."
    }
    precondition {
      condition     = alltrue([for az in var.azs : startswith(az, var.aws_region)])
      error_message = "Every availability zone must belong to aws_region."
    }
    precondition {
      condition     = strcontains(var.docker_image, ".dkr.ecr.${var.aws_region}.amazonaws.com/")
      error_message = "The private ECR image must be in aws_region."
    }
  }
}
