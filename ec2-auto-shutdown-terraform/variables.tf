variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "eu-central-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "ec2-auto-shutdown"
}

variable "cpu_threshold" {
  description = "CPU utilization threshold (%) below which instance is considered idle"
  type        = number
  default     = 10
}

variable "network_threshold" {
  description = "Network activity threshold (bytes) below which instance is considered idle"
  type        = number
  default     = 100000
}

variable "disk_threshold" {
  description = "Disk I/O threshold (bytes) below which instance is considered idle"
  type        = number
  default     = 5000000
}

variable "inactivity_hours" {
  description = "Hours of inactivity before instance shutdown"
  type        = number
  default     = 3
}

variable "metric_period" {
  description = "CloudWatch metric period in seconds"
  type        = number
  default     = 300
}

variable "log_level" {
  description = "Lambda function log level (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "DEBUG"
}

variable "schedule_rate" {
  description = "Rate expression for EventBridge scheduled check (e.g., rate(30 minutes))"
  type        = string
  default     = "rate(30 minutes)"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 900
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
}

variable "log_retention_days" {
  description = "CloudWatch logs retention in days"
  type        = number
  default     = 30
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "EC2AutoShutdown"
    ManagedBy = "Terraform"
  }
}

variable "teams_webhook_urls" {
  description = "List of Microsoft Teams Incoming Webhook URLs for notifications"
  type        = list(string)
  default     = []
  sensitive   = true
}
