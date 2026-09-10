output "alb_dns_name" {
  description = "DNS-адреса Load Balancer - сюди curl / artillery target"
  value       = aws_lb.app.dns_name
}

output "asg_name" {
  description = "Назва Auto Scaling Group"
  value       = module.asg.autoscaling_group_name
}

output "target_group_arn" {
  description = "ARN Target Group"
  value       = aws_lb_target_group.app.arn
}

output "vpc_id" {
  description = "ID створеного VPC"
  value       = module.vpc.vpc_id
}

output "sns_topic_arn" {
  description = "ARN SNS-топіка для алярмів"
  value       = aws_sns_topic.alerts.arn
}

output "app_url" {
  description = "Public HTTP application URL"
  value       = "http://${aws_lb.app.dns_name}"
}

output "aws_region" {
  value = var.aws_region
}
