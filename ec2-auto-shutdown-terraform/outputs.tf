output "lambda_function_arn" {
  description = "ARN of the EC2 Auto Shutdown Lambda function"
  value       = aws_lambda_function.auto_shutdown.arn
}

output "lambda_function_name" {
  description = "Name of the EC2 Auto Shutdown Lambda function"
  value       = aws_lambda_function.auto_shutdown.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "scheduled_rule_name" {
  description = "Name of the EventBridge scheduled rule"
  value       = aws_cloudwatch_event_rule.scheduled_check.name
}

output "ec2_state_change_rule_name" {
  description = "Name of the EventBridge EC2 state change rule"
  value       = aws_cloudwatch_event_rule.ec2_state_change.name
}

output "ec2_launch_rule_name" {
  description = "Name of the EventBridge EC2 launch rule"
  value       = aws_cloudwatch_event_rule.ec2_launch.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for shutdown notifications"
  value       = aws_sns_topic.shutdown_notifications.arn
}

output "teams_notifier_function_name" {
  description = "Name of the Teams Notifier Lambda function (if enabled)"
  value       = length(var.teams_webhook_urls) > 0 ? aws_lambda_function.teams_notifier[0].function_name : "Not enabled"
  sensitive   = true
}
