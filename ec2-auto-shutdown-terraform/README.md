# EC2 Auto Shutdown - Terraform

A Terraform solution for automatically shutting down idle EC2 instances based on CloudWatch metrics.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐
│   EventBridge   │    │   EventBridge    │
│   (Schedule)    │    │   (EC2 Events)   │
│  every 30 mins  │    │  state "running" │
└─────────┬───────┘    └────────┬─────────┘
          │                     │
          └─────────┬───────────┘
                    │
            ┌───────▼────────┐
            │  Lambda Function│
            │  (Auto Shutdown)│
            └─────────────────┘
```

## Features

- **Scheduled Monitoring**: Checks all instances every 30 minutes (default)
- **Event-Driven**: Immediately monitors new instances when they start running
- **Configurable Thresholds**: CPU, network, and disk I/O thresholds via environment variables
- **Safe Operation**: Only processes instances with `AutoShutdownEnabled=true` tag
- **Comprehensive Logging**: CloudWatch logs with configurable verbosity level
- **Teams Notifications**: Sends beautifully formatted notifications to Microsoft Teams (optional)

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- AWS Account with permissions to create:
  - Lambda Functions
  - IAM Roles and Policies
  - EventBridge Rules
  - CloudWatch Log Groups

## Deployment

### Quick Start

The solution includes built-in **default values in `variables.tf`**, allowing deployment without additional configuration:

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   ```
   
   then navigate to the directory:
   ```bash
   cd ec2-auto-shutdown-terraform
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Review the deployment plan**:
   ```bash
   terraform plan
   ```

4. **Deploy infrastructure**:
   ```bash
   terraform apply
   ```

## Configuration

### Customizing configuration

If you want to **customize thresholds** for your needs, copy the example configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars`:

```hcl
# Example variable configuration
# Copy this file to terraform.tfvars and adjust values

# Basic configuration
aws_region           = "eu-central-1"
lambda_function_name = "ec2-auto-shutdown"

# Inactivity thresholds
cpu_threshold      = 10        # CPU utilization threshold (%)
network_threshold  = 100000    # Network activity threshold (bytes)
disk_threshold     = 5000000   # Disk I/O threshold (bytes) - 5 MB
inactivity_hours   = 3         # Hours of inactivity before shutdown
metric_period      = 300       # CloudWatch metric period (seconds)

# Lambda configuration
lambda_timeout     = 900       # Lambda function timeout (seconds)
lambda_memory_size = 256       # Lambda function memory (MB)
log_level          = "DEBUG"   # Log level (DEBUG, INFO, WARNING, ERROR)

# Schedule
schedule_rate = "rate(30 minutes)"  # Check frequency

# Log retention
log_retention_days = 30        # CloudWatch log retention (days)

# Tags
default_tags = {
  Project     = "EC2AutoShutdown"
  Environment = "Development"
  ManagedBy   = "Terraform"
  Owner       = "DevOps"
}

# Teams notifications - you can add multiple webhooks for different channels
teams_webhook_urls = [
  # "https://yourcompany.webhook.office.com/webhookb2/xxx/IncomingWebhook/xxx/xxx",
  # "https://yourcompany.webhook.office.com/webhookb2/yyy/IncomingWebhook/yyy/yyy"
]

```

### EC2 Instance Configuration

To enable automatic shutdown for an EC2 instance, add a tag:

```
Key: AutoShutdownEnabled
Value: true
```

#### Via AWS CLI:

```bash
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=AutoShutdownEnabled,Value=true
```

## How It Works

1. **Instance Detection**: Lambda scans running instances with `AutoShutdownEnabled=true` tag
2. **Metrics Analysis**: Checks CloudWatch metrics for CPU, network, and disk activity from the last 3 hours
3. **Inactivity Tracking**: Uses EC2 tags to track when inactivity started
4. **Shutdown Decision**: Stops instances idle for the configured time
5. **Tagging**: Maintains `InactivityStart` and `LastActivityCheck` tags to track status

## CloudWatch Metrics

### Metrics Used (namespace `AWS/EC2`):

#### Basic Metrics (always available):
| Metric | Availability | Description |
|--------|--------------|-------------|
| `CPUUtilization` | ✅ All instances | CPU usage (%) |
| `NetworkIn` | ✅ All instances | Inbound traffic (bytes) |
| `NetworkOut` | ✅ All instances | Outbound traffic (bytes) |

#### Disk Metrics (optional):
| Metric | Availability | Description |
|--------|--------------|-------------|
| `EBSReadBytes` | ⚠️ EBS instances | Read from EBS volumes (bytes) |
| `EBSWriteBytes` | ⚠️ EBS instances | Write to EBS volumes (bytes) |
| `DiskReadBytes` | ⚠️ Instance Store only | Disk read (bytes) |
| `DiskWriteBytes` | ⚠️ Instance Store only | Disk write (bytes) |

### 📝 Important Information About Disk Metrics:

**Intelligent Metric Detection:**
- Lambda automatically checks availability of EBS or Instance Store metrics
- Instance has **either** EBS **or** Instance Store metrics (not both)
- If available → includes them in inactivity analysis
- If no disk metrics → bases decision on CPU + Network only

**Instance Types:**

**Instances with EBS volumes** (most common, e.g., t3, m5, c5):
- Metrics: `CPUUtilization`, `NetworkIn/Out`
- Optionally: `EBSReadBytes`, `EBSWriteBytes` (if available)

**Instances with Instance Store** (e.g., c5d, m5d, r5d, i3, d2):
- Metrics: `CPUUtilization`, `NetworkIn/Out`
- Additionally: `DiskReadBytes`, `DiskWriteBytes` (available by default)

### Logic:
1. Checks availability of `EBSReadBytes/EBSWriteBytes`
2. If not found → checks `DiskReadBytes/DiskWriteBytes`
3. If disk metrics available → checks CPU + Network + Disk
4. If no disk metrics → checks only CPU + Network
5. Instance considered idle when **all available metrics** are below thresholds

## EventBridge Rules

### 1. Scheduled Rule
- **Frequency**: Every 30 minutes (default)
- **Purpose**: Regular checking of all running instances
- **Expression**: `rate(30 minutes)`

### 2. EC2 State Change Rule
- **Trigger**: When instances transition to "running" state
- **Purpose**: Immediate monitoring of new instances

### 3. EC2 Launch Rule
- **Trigger**: When new instances are launching (pending or running)
- **Purpose**: Early detection and tagging of instances

## IAM Permissions

Lambda function requires the following permissions:

### EC2 Permissions
- `ec2:DescribeInstances`
- `ec2:DescribeTags`
- `ec2:StopInstances`
- `ec2:CreateTags`
- `ec2:DeleteTags`

### CloudWatch Permissions
- `cloudwatch:GetMetricStatistics`
- `cloudwatch:ListMetrics`

## Monitoring

### CloudWatch Logs
- Log Group: `/aws/lambda/ec2-auto-shutdown`
- Retention: 30 days (default)
- Log Level: Configurable via variable

### Key Log Messages
- Instance processing start/completion
- Metrics analysis results
- Shutdown decisions and actions
- Errors and warnings

## Testing

### Manual Lambda Testing

```bash
# Test scheduled event
aws lambda invoke \
  --function-name ec2-auto-shutdown \
  --payload '{"source": "aws.events"}' \
  response.json

# Test EC2 state change event
aws lambda invoke \
  --function-name ec2-auto-shutdown \
  --payload '{
    "source": "aws.ec2",
    "detail": {
      "instance-id": "i-1234567890abcdef0",
      "state": "running"
    }
  }' \
  response.json
```

### Using Verification Script

```bash
./scripts/verify.sh
```

### View Logs

```bash
# Real-time log viewing
aws logs tail /aws/lambda/ec2-auto-shutdown --follow

# Last 1 hour of logs
aws logs tail /aws/lambda/ec2-auto-shutdown --since 1h
```

## Notifications

### Microsoft Teams

The solution can send beautifully formatted notifications to Microsoft Teams when an instance is shut down.

#### Example Teams Message:

```
🔴 EC2 Instance Shutdown
Automatic shutdown due to inactivity

Name:           my-dev-server
Instance ID:    i-1234567890abcdef0
Idle Time:      3.52 hours
Avg CPU:        4.23%
Avg Network:    45231 bytes
Disk Type:      EBS
Timestamp:      2025-11-20 10:30:15 UTC
```

#### Configuring Teams Webhook:

1. **Create Incoming Webhook in Teams**:
   - Go to the Teams channel where you want to receive notifications
   - Click `...` → `Connectors` → `Incoming Webhook`
   - Configure webhook and copy URL

2. **Add to `terraform.tfvars`** (you can add multiple channels):
   ```hcl
   teams_webhook_urls = [
     "https://yourteam.webhook.office.com/webhookb2/xxx/IncomingWebhook/xxx/xxx",
     "https://yourteam.webhook.office.com/webhookb2/yyy/IncomingWebhook/yyy/yyy"  # Second channel (optional)
   ]
   ```

3. **Deploy infrastructure**:
   ```bash
   terraform apply
   ```

#### Notification Architecture:

```
Main Lambda → SNS Topic → Teams Notifier Lambda → Teams Webhook(s)
```

## Customization

### Changing Thresholds

Edit `terraform.tfvars`:

```hcl
cpu_threshold      = 15       # 15% CPU
network_threshold  = 50000    # 50KB network
inactivity_hours   = 2        # 2 hours
```

Then apply changes:

```bash
terraform apply
```

### Changing Schedule

Edit `terraform.tfvars`:

```hcl
# Every 15 minutes
schedule_rate = "rate(15 minutes)"

# Or cron expression (business hours only)
schedule_rate = "cron(0 9-17 ? * MON-FRI *)"
```

### Changing AWS Region

Edit `terraform.tfvars`:

```hcl
aws_region = "eu-central-1"
```

## File Structure

```
ec2-auto-shutdown-terraform/
├── provider.tf          # Terraform providers configuration
├── variables.tf         # Variable declarations
├── main.tf             # Main infrastructure resources
├── outputs.tf          # Terraform outputs
├── terraform.tfvars    # Variable values (optional)
├── lambda/             # Lambda function code
│   ├── lambda_function.py
│   ├── teams_notifier.py
│   └── requirements.txt
├── scripts/            # Helper scripts
│   └── verify.sh       # Deployment verification script
└── README.md           # This documentation
```

## Security Considerations

1. **Minimal Permissions**: IAM role has only required permissions
2. **Tag-Based Control**: Only processes explicitly tagged instances
3. **Audit Trail**: All actions are logged in CloudWatch
4. **No External Dependencies**: Uses only native AWS services
5. **Terraform State**: Store Terraform state in a secure location (S3 + DynamoDB)

## Cost Optimization

- **Lambda Costs**: Pay-per-execution model, typically < $5/month
- **EventBridge**: First 14 million events per month are free
- **CloudWatch Logs**: 30-day retention keeps costs minimal
- **Savings**: Can reduce EC2 costs by 40-60% for development environments

## Troubleshooting

### Common Issues

1. **No instances being processed**
   - Check if `AutoShutdownEnabled=true` tag exists
   - Review Lambda function logs for errors

2. **Instances not shutting down**
   - Verify thresholds are appropriate
   - Ensure instances have sufficient metrics history

3. **Permission errors**
   - Verify Lambda role has required EC2 and CloudWatch permissions
   - Check for SCPs or permission boundaries blocking access

4. **Terraform errors**
   - Run `terraform validate` to check syntax
   - Ensure AWS credentials are properly configured

## Cleanup

To remove all resources created by this Terraform stack:

```bash
terraform destroy
```

This will remove:
- Lambda function
- IAM role and policies
- EventBridge rules
- CloudWatch log group

## Outputs

After deployment, Terraform will display:

- `lambda_function_arn` - Lambda function ARN
- `lambda_function_name` - Lambda function name
- `lambda_role_arn` - Lambda IAM role ARN
- `log_group_name` - CloudWatch log group name
- `scheduled_rule_name` - Scheduled EventBridge rule name
- `ec2_state_change_rule_name` - EC2 state change rule name
- `ec2_launch_rule_name` - EC2 launch rule name

## Support

For issues or questions:
1. Check CloudWatch logs for detailed error messages
2. Verify IAM permissions and EC2 tags
3. Test with manual Lambda invocations
4. Review EventBridge rule configurations

## License

This project is provided as an educational example. Customize it to your needs.
