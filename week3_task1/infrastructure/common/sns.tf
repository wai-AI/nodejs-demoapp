resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-app-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Real scaling events, in addition to CloudWatch CPU/health alarms.
resource "aws_autoscaling_notification" "scaling_events" {
  group_names = [module.asg.autoscaling_group_name]
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]
  topic_arn = aws_sns_topic.alerts.arn
}
