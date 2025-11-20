# Data source for packaging Lambda code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/builds/lambda.zip"
}

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_role" {
  name        = "${var.lambda_function_name}-role"
  description = "Role for EC2 Auto Shutdown Lambda function"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda to access EC2 and CloudWatch
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.lambda_function_name}-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:StopInstances",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = var.log_retention_days
}

# Lambda Function
resource "aws_lambda_function" "auto_shutdown" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  description      = "Automatically shuts down idle EC2 instances based on CloudWatch metrics"

  environment {
    variables = {
      CPU_THRESHOLD     = var.cpu_threshold
      NETWORK_THRESHOLD = var.network_threshold
      DISK_THRESHOLD    = var.disk_threshold
      INACTIVITY_HOURS  = var.inactivity_hours
      METRIC_PERIOD     = var.metric_period
      LOG_LEVEL         = var.log_level
      SNS_TOPIC_ARN     = aws_sns_topic.shutdown_notifications.arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_policy
  ]
}

# EventBridge Rule - Scheduled execution
resource "aws_cloudwatch_event_rule" "scheduled_check" {
  name                = "ec2-auto-shutdown-schedule"
  description         = "Triggers EC2 auto shutdown function on schedule: ${var.schedule_rate}"
  schedule_expression = var.schedule_rate
}

# EventBridge Target for scheduled rule
resource "aws_cloudwatch_event_target" "scheduled_check_target" {
  rule      = aws_cloudwatch_event_rule.scheduled_check.name
  target_id = "LambdaFunction"
  arn       = aws_lambda_function.auto_shutdown.arn
}

# Lambda permission for EventBridge scheduled rule
resource "aws_lambda_permission" "allow_eventbridge_scheduled" {
  statement_id  = "AllowExecutionFromEventBridgeScheduled"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_shutdown.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scheduled_check.arn
}

# EventBridge Rule - EC2 Instance State Changes (running)
resource "aws_cloudwatch_event_rule" "ec2_state_change" {
  name        = "ec2-instance-state-change"
  description = "Triggers when EC2 instances change state to running"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["running"]
    }
  })
}

# EventBridge Target for EC2 state change rule
resource "aws_cloudwatch_event_target" "ec2_state_change_target" {
  rule      = aws_cloudwatch_event_rule.ec2_state_change.name
  target_id = "LambdaFunction"
  arn       = aws_lambda_function.auto_shutdown.arn
}

# Lambda permission for EventBridge EC2 state change
resource "aws_lambda_permission" "allow_eventbridge_ec2_state" {
  statement_id  = "AllowExecutionFromEventBridgeEC2State"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_shutdown.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_state_change.arn
}

# EventBridge Rule - EC2 Instance Launch (pending or running)
resource "aws_cloudwatch_event_rule" "ec2_launch" {
  name        = "ec2-instance-launch"
  description = "Triggers when new EC2 instances are launched"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["pending", "running"]
    }
  })
}

# EventBridge Target for EC2 launch rule
resource "aws_cloudwatch_event_target" "ec2_launch_target" {
  rule      = aws_cloudwatch_event_rule.ec2_launch.name
  target_id = "LambdaFunction"
  arn       = aws_lambda_function.auto_shutdown.arn
}

# Lambda permission for EventBridge EC2 launch
resource "aws_lambda_permission" "allow_eventbridge_ec2_launch" {
  statement_id  = "AllowExecutionFromEventBridgeEC2Launch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_shutdown.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_launch.arn
}

# SNS Topic for notifications
resource "aws_sns_topic" "shutdown_notifications" {
  name         = "${var.lambda_function_name}-notifications"
  display_name = "EC2 Auto Shutdown Notifications"
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "shutdown_notifications" {
  arn = aws_sns_topic.shutdown_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.shutdown_notifications.arn
      }
    ]
  })
}

# Update Lambda role to allow SNS publish
resource "aws_iam_role_policy" "lambda_sns_policy" {
  name = "${var.lambda_function_name}-sns-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.shutdown_notifications.arn
      }
    ]
  })
}

# Data source for packaging Teams notifier Lambda code
data "archive_file" "teams_notifier_zip" {
  count       = length(var.teams_webhook_urls) > 0 ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/teams_notifier.py"
  output_path = "${path.module}/builds/teams_notifier.zip"
}

# IAM Role for Teams Notifier Lambda
resource "aws_iam_role" "teams_notifier_role" {
  count       = length(var.teams_webhook_urls) > 0 ? 1 : 0
  name        = "${var.lambda_function_name}-teams-notifier-role"
  description = "Role for Teams Notifier Lambda function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution to Teams Notifier
resource "aws_iam_role_policy_attachment" "teams_notifier_basic_execution" {
  count      = length(var.teams_webhook_urls) > 0 ? 1 : 0
  role       = aws_iam_role.teams_notifier_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch Log Group for Teams Notifier
resource "aws_cloudwatch_log_group" "teams_notifier_logs" {
  count             = length(var.teams_webhook_urls) > 0 ? 1 : 0
  name              = "/aws/lambda/${var.lambda_function_name}-teams-notifier"
  retention_in_days = var.log_retention_days
}

# Teams Notifier Lambda Function
resource "aws_lambda_function" "teams_notifier" {
  count            = length(var.teams_webhook_urls) > 0 ? 1 : 0
  filename         = data.archive_file.teams_notifier_zip[0].output_path
  function_name    = "${var.lambda_function_name}-teams-notifier"
  role             = aws_iam_role.teams_notifier_role[0].arn
  handler          = "teams_notifier.lambda_handler"
  source_code_hash = data.archive_file.teams_notifier_zip[0].output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 128
  description      = "Sends EC2 shutdown notifications to Microsoft Teams"

  environment {
    variables = {
      TEAMS_WEBHOOK_URLS = jsonencode(var.teams_webhook_urls)
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.teams_notifier_logs[0],
    aws_iam_role_policy_attachment.teams_notifier_basic_execution[0]
  ]
}

# SNS Subscription for Teams Notifier Lambda
resource "aws_sns_topic_subscription" "teams_notifier" {
  count     = length(var.teams_webhook_urls) > 0 ? 1 : 0
  topic_arn = aws_sns_topic.shutdown_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.teams_notifier[0].arn
}

# Lambda permission for SNS to invoke Teams Notifier
resource "aws_lambda_permission" "allow_sns_teams_notifier" {
  count         = length(var.teams_webhook_urls) > 0 ? 1 : 0
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.teams_notifier[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.shutdown_notifications.arn
}
