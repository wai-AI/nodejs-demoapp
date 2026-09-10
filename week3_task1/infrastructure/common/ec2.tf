data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_lb" "app" {
  name               = "${var.environment}-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets
  idle_timeout       = 60 # Node keepAliveTimeout in the fork is 65 seconds.

  tags = {
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.environment}-app-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
    port                = "traffic-port"
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Auto Scaling Group з launch template, IAM-роллю для ECR pull та
# target tracking scaling policy по CPU. Мережу (SG) модуль не створює -
# вони описані в network.tf і передаються сюди готовими.
module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "8.3.1"

  name = "${var.environment}-app-asg"

  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = module.vpc.private_subnets

  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type
  key_name      = var.key_name

  security_groups = [aws_security_group.asg_sg.id]

  # path.module is dev/ or production/; both share this template.
  user_data = base64encode(templatefile(
    "${path.module}/../../user_data/user_data.sh",
    {
      docker_image      = var.docker_image
      app_port          = var.app_port
      container_port    = var.container_port
      health_check_path = var.health_check_path
      aws_region        = var.aws_region
    }
  ))

  traffic_source_attachments = {
    alb = {
      traffic_source_identifier = aws_lb_target_group.app.arn
      traffic_source_type       = "elbv2"
    }
  }
  health_check_type         = "ELB"
  health_check_grace_period = 600
  default_instance_warmup   = 180
  enable_monitoring         = true

  # Scaling policies own desired capacity after creation.
  ignore_desired_capacity_changes = true

  # A changed image URI/user-data creates a new launch template version.
  # Replace existing instances, including the single-instance dev group.
  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 180
      skip_matching          = true
    }
  }

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Subnet IDs alone do not wait for NAT routes. Bootstrap needs Internet
  # access for dnf/ECR, and ELB health checks need the listener to exist.
  depends_on = [module.vpc, aws_lb_listener.http]

  # IAM instance profile, щоб інстанси могли робити docker pull з ECR
  create_iam_instance_profile = true
  iam_role_name               = "${var.environment}-asg-role"
  iam_role_description        = "Allows ASG instances to pull the app image from ECR"
  iam_role_policies = {
    ecr_read = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    ssm      = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # Автоскейлінг за середнім CPU по групі - вбудований механізм модуля,
  # окремий aws_autoscaling_policy ресурс не потрібен
  scaling_policies = {
    cpu-target-tracking = {
      policy_type = "TargetTrackingScaling"
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
        target_value = 50.0
      }
    }
  }

  tags = {
    Environment = var.environment
  }
}

# Preserve the existing ASG when switching the module to ignore desired capacity.
moved {
  from = module.asg.aws_autoscaling_group.this[0]
  to   = module.asg.aws_autoscaling_group.idc[0]
}
