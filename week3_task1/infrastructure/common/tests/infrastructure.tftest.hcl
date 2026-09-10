mock_provider "aws" {}

variables {
  docker_image = "123456789012.dkr.ecr.eu-central-1.amazonaws.com/nodejs-demoapp:test"
}

run "network_and_bootstrap" {
  command = plan

  assert {
    condition     = aws_lb.app.internal == false && aws_lb.app.idle_timeout == 60
    error_message = "The public ALB must use a 60-second idle timeout."
  }

  assert {
    condition     = aws_lb_target_group.app.port == var.app_port && aws_lb_target_group.app.health_check[0].path == "/healthz" && aws_lb_target_group.app.health_check[0].matcher == "200"
    error_message = "Traffic and strict readiness checks must reach the configured host port."
  }

  assert {
    condition     = length(aws_autoscaling_notification.scaling_events.notifications) == 4
    error_message = "Publish launch/terminate successes and failures to SNS."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.no_healthy_hosts.treat_missing_data == "breaching"
    error_message = "Missing targets must not hide an outage."
  }
}

run "reject_invalid_capacity" {
  command = plan
  variables {
    asg_min_size         = 3
    asg_desired_capacity = 2
    asg_max_size         = 4
  }
  expect_failures = [terraform_data.configuration]
}

run "reject_cross_region_image" {
  command = plan
  variables {
    docker_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/nodejs-demoapp:test"
  }
  expect_failures = [terraform_data.configuration]
}

run "reject_single_az" {
  command = plan
  variables {
    azs             = ["eu-central-1a"]
    public_subnets  = ["10.0.1.0/24"]
    private_subnets = ["10.0.11.0/24"]
  }
  expect_failures = [terraform_data.configuration]
}
