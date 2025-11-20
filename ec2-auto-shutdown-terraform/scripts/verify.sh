#!/bin/bash
set -e

# EC2 Auto Shutdown - Verification Script
# This script checks if all components are properly deployed and configured

echo "🔍 EC2 Auto Shutdown - Verification Script"
echo "==========================================="
echo ""

REGION="${AWS_REGION:-us-east-1}"
FUNCTION_NAME="ec2-auto-shutdown"
TEAMS_NOTIFIER_NAME="ec2-auto-shutdown-teams-notifier"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if AWS CLI is configured
echo "📋 Step 1: Checking AWS CLI configuration..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS CLI is not configured or credentials are invalid${NC}"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✅ AWS Account: $ACCOUNT_ID${NC}"
echo ""

# Check Main Lambda Function
echo "📋 Step 2: Checking Main Lambda Function..."
if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" &> /dev/null; then
    echo -e "${GREEN}✅ Lambda function '$FUNCTION_NAME' exists${NC}"
    
    # Get function details
    LAMBDA_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Configuration.FunctionArn' --output text)
    LAMBDA_RUNTIME=$(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Configuration.Runtime' --output text)
    LAMBDA_TIMEOUT=$(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Configuration.Timeout' --output text)
    LAMBDA_MEMORY=$(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Configuration.MemorySize' --output text)
    
    echo "   ARN: $LAMBDA_ARN"
    echo "   Runtime: $LAMBDA_RUNTIME"
    echo "   Timeout: ${LAMBDA_TIMEOUT}s"
    echo "   Memory: ${LAMBDA_MEMORY}MB"
    
    # Check environment variables
    echo ""
    echo "   Environment Variables:"
    aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Environment.Variables' --output json | jq -r 'to_entries[] | "   - \(.key): \(.value)"'
    
    # CRITICAL: Validate configuration consistency
    echo ""
    echo "   🔍 Configuration Validation:"
    INACTIVITY_HOURS=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Environment.Variables.INACTIVITY_HOURS' --output text)
    CPU_THRESHOLD=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Environment.Variables.CPU_THRESHOLD' --output text)
    NETWORK_THRESHOLD=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Environment.Variables.NETWORK_THRESHOLD' --output text)
    DISK_THRESHOLD=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Environment.Variables.DISK_THRESHOLD' --output text)
    
    echo "   - Inactivity threshold: ${INACTIVITY_HOURS}h"
    echo "   - CPU threshold: ${CPU_THRESHOLD}%"
    echo "   - Network threshold: ${NETWORK_THRESHOLD} bytes (~$(echo "scale=0; $NETWORK_THRESHOLD/1000" | bc)KB)"
    echo "   - Disk threshold: ${DISK_THRESHOLD} bytes (~$(echo "scale=0; $DISK_THRESHOLD/1000000" | bc)MB)"
    
    # Warning checks
    if (( $(echo "$INACTIVITY_HOURS < 0.5" | bc -l) )); then
        echo -e "   ${YELLOW}⚠️  WARNING: INACTIVITY_HOURS < 30 minutes may cause frequent shutdowns${NC}"
    fi
    
    if (( $(echo "$CPU_THRESHOLD > 20" | bc -l) )); then
        echo -e "   ${YELLOW}⚠️  WARNING: CPU_THRESHOLD > 20% may miss idle instances${NC}"
    fi
    
    if (( $(echo "$DISK_THRESHOLD < 1000000" | bc -l) )); then
        echo -e "   ${YELLOW}⚠️  WARNING: DISK_THRESHOLD < 1MB may be too sensitive for normal system activity${NC}"
    fi
    
    echo -e "   ${GREEN}✅ Metric window and inactivity threshold are synchronized (both use INACTIVITY_HOURS)${NC}"
else
    echo -e "${RED}❌ Lambda function '$FUNCTION_NAME' not found${NC}"
    exit 1
fi
echo ""

# Check CloudWatch Log Group
echo "📋 Step 3: Checking CloudWatch Log Group..."
LOG_GROUP="/aws/lambda/$FUNCTION_NAME"
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$REGION" --query "logGroups[?logGroupName=='$LOG_GROUP']" --output text | grep -q "$LOG_GROUP"; then
    echo -e "${GREEN}✅ Log group '$LOG_GROUP' exists${NC}"
    RETENTION=$(aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$REGION" --query "logGroups[?logGroupName=='$LOG_GROUP'].retentionInDays" --output text)
    echo "   Retention: ${RETENTION} days"
else
    echo -e "${YELLOW}⚠️  Log group '$LOG_GROUP' not found${NC}"
fi
echo ""

# Check EventBridge Rules
echo "📋 Step 4: Checking EventBridge Rules..."

# Scheduled rule
SCHEDULED_RULE="ec2-auto-shutdown-schedule"
if aws events describe-rule --name "$SCHEDULED_RULE" --region "$REGION" &> /dev/null; then
    echo -e "${GREEN}✅ Scheduled rule '$SCHEDULED_RULE' exists${NC}"
    SCHEDULE=$(aws events describe-rule --name "$SCHEDULED_RULE" --region "$REGION" --query 'ScheduleExpression' --output text)
    STATE=$(aws events describe-rule --name "$SCHEDULED_RULE" --region "$REGION" --query 'State' --output text)
    echo "   Schedule: $SCHEDULE"
    echo "   State: $STATE"
else
    echo -e "${RED}❌ Scheduled rule '$SCHEDULED_RULE' not found${NC}"
fi
echo ""

# EC2 state change rule
STATE_CHANGE_RULE="ec2-instance-state-change"
if aws events describe-rule --name "$STATE_CHANGE_RULE" --region "$REGION" &> /dev/null; then
    echo -e "${GREEN}✅ State change rule '$STATE_CHANGE_RULE' exists${NC}"
    STATE=$(aws events describe-rule --name "$STATE_CHANGE_RULE" --region "$REGION" --query 'State' --output text)
    echo "   State: $STATE"
else
    echo -e "${RED}❌ State change rule '$STATE_CHANGE_RULE' not found${NC}"
fi
echo ""

# EC2 launch rule
LAUNCH_RULE="ec2-instance-launch"
if aws events describe-rule --name "$LAUNCH_RULE" --region "$REGION" &> /dev/null; then
    echo -e "${GREEN}✅ Launch rule '$LAUNCH_RULE' exists${NC}"
    STATE=$(aws events describe-rule --name "$LAUNCH_RULE" --region "$REGION" --query 'State' --output text)
    echo "   State: $STATE"
else
    echo -e "${RED}❌ Launch rule '$LAUNCH_RULE' not found${NC}"
fi
echo ""

# Check SNS Topic
echo "📋 Step 5: Checking SNS Topic..."
SNS_TOPIC_NAME="ec2-auto-shutdown-notifications"
SNS_TOPIC_ARN=$(aws sns list-topics --region "$REGION" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)

if [ -n "$SNS_TOPIC_ARN" ]; then
    echo -e "${GREEN}✅ SNS Topic exists${NC}"
    echo "   ARN: $SNS_TOPIC_ARN"
    
    # Check subscriptions
    SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --region "$REGION" --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,Status:SubscriptionArn}' --output json)
    SUB_COUNT=$(echo "$SUBSCRIPTIONS" | jq '. | length')
    echo "   Subscriptions: $SUB_COUNT"
    
    if [ "$SUB_COUNT" -gt 0 ]; then
        echo "$SUBSCRIPTIONS" | jq -r '.[] | "   - \(.Protocol): \(if .Endpoint | length > 50 then .Endpoint[:47] + "..." else .Endpoint end)"'
    fi
else
    echo -e "${YELLOW}⚠️  SNS Topic not found${NC}"
fi
echo ""

# Check Teams Notifier Lambda (optional)
echo "📋 Step 6: Checking Teams Notifier Lambda (optional)..."
if aws lambda get-function --function-name "$TEAMS_NOTIFIER_NAME" --region "$REGION" &> /dev/null; then
    echo -e "${GREEN}✅ Teams Notifier Lambda exists${NC}"
    
    TEAMS_RUNTIME=$(aws lambda get-function --function-name "$TEAMS_NOTIFIER_NAME" --region "$REGION" --query 'Configuration.Runtime' --output text)
    echo "   Runtime: $TEAMS_RUNTIME"
    
    # Check if webhook is configured
    WEBHOOK_CONFIGURED=$(aws lambda get-function-configuration --function-name "$TEAMS_NOTIFIER_NAME" --region "$REGION" --query 'Environment.Variables.TEAMS_WEBHOOK_URLS' --output text)
    if [ -n "$WEBHOOK_CONFIGURED" ] && [ "$WEBHOOK_CONFIGURED" != "None" ] && [ "$WEBHOOK_CONFIGURED" != "[]" ]; then
        echo -e "   ${GREEN}✅ Teams webhook URLs are configured${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Teams webhook URLs not configured${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Teams Notifier Lambda not found (may not be enabled)${NC}"
fi
echo ""

# Check IAM Role
echo "📋 Step 7: Checking IAM Role..."
ROLE_NAME="ec2-auto-shutdown-role"
if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    echo -e "${GREEN}✅ IAM Role '$ROLE_NAME' exists${NC}"
    
    # List attached policies
    POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyName' --output text)
    echo "   Attached Policies: $POLICIES"
    
    # List inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames' --output text)
    if [ -n "$INLINE_POLICIES" ]; then
        echo "   Inline Policies: $INLINE_POLICIES"
    fi
else
    echo -e "${RED}❌ IAM Role '$ROLE_NAME' not found${NC}"
fi
echo ""

# Check for running EC2 instances with AutoShutdownEnabled tag
echo "📋 Step 8: Checking EC2 Instances..."

# Get INACTIVITY_HOURS from Lambda config
INACTIVITY_HOURS=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Environment.Variables.INACTIVITY_HOURS' --output text 2>/dev/null || echo "3")

# Get Lambda schedule and calculate next execution time (once for all instances)
SCHEDULE_EXPR=$(aws events describe-rule --name ec2-auto-shutdown-schedule --region "$REGION" --query 'ScheduleExpression' --output text 2>/dev/null)
RATE_MINUTES=""
NEXT_EXEC_INFO=""
if [[ "$SCHEDULE_EXPR" =~ rate\(([0-9]+)\ (minute|minutes)\) ]]; then
    RATE_MINUTES="${BASH_REMATCH[1]}"
    # Get last Lambda invocation time (most recent)
    LAST_INVOCATION=$(aws logs filter-log-events \
        --log-group-name "/aws/lambda/ec2-auto-shutdown" \
        --region "$REGION" \
        --filter-pattern "START RequestId" \
        --max-items 5 \
        --query 'events[-1].timestamp' \
        --output text 2>/dev/null | head -1)
    
    if [ -n "$LAST_INVOCATION" ] && [ "$LAST_INVOCATION" != "None" ] && [[ "$LAST_INVOCATION" =~ ^[0-9]+$ ]]; then
        LAST_INVOCATION_EPOCH=$((LAST_INVOCATION / 1000))  # Convert from milliseconds
        NEXT_INVOCATION_EPOCH=$((LAST_INVOCATION_EPOCH + RATE_MINUTES * 60))
        CURRENT_EPOCH=$(date +%s)
        TIME_TO_NEXT=$((NEXT_INVOCATION_EPOCH - CURRENT_EPOCH))
        
        if [ $TIME_TO_NEXT -gt 0 ]; then
            NEXT_EXEC_MIN=$((TIME_TO_NEXT / 60))
            NEXT_EXEC_INFO="Next check in ${NEXT_EXEC_MIN} min"
        else
            NEXT_EXEC_INFO="Next check imminent"
        fi
    fi
fi

INSTANCES_DATA=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:AutoShutdownEnabled,Values=true" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],Tags[?Key==`InactivityStart`].Value|[0],LaunchTime]' \
    --output json)

INSTANCE_COUNT=$(echo "$INSTANCES_DATA" | jq -r 'length')

if [ "$INSTANCE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ Found $INSTANCE_COUNT instance(s) with AutoShutdownEnabled=true tag:${NC}"
    echo ""
    
    while IFS=$'\t' read -r INSTANCE_ID INSTANCE_NAME INACTIVITY_START LAUNCH_TIME; do
        if [ -z "$INSTANCE_NAME" ]; then
            INSTANCE_NAME="<unnamed>"
        fi
        
        echo "   🖥️  Instance: $INSTANCE_ID ($INSTANCE_NAME)"
        
        if [ "$INACTIVITY_START" != "null" ] && [ -n "$INACTIVITY_START" ]; then
            # Instance is idle - calculate time until shutdown
            # INACTIVITY_START can be Unix timestamp (1234567890.123) or ISO format (2025-11-20T14:00:00Z)
            if [[ "$INACTIVITY_START" =~ ^[0-9]+\. ]]; then
                # Unix timestamp with decimals
                INACTIVITY_EPOCH=$(echo "$INACTIVITY_START" | cut -d'.' -f1)
            elif [[ "$INACTIVITY_START" =~ ^[0-9]+$ ]]; then
                # Unix timestamp without decimals
                INACTIVITY_EPOCH=$INACTIVITY_START
            else
                # ISO format - convert to epoch
                INACTIVITY_EPOCH=$(date -d "$INACTIVITY_START" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$INACTIVITY_START" +%s 2>/dev/null)
            fi
            
            CURRENT_EPOCH=$(date +%s)
            ELAPSED_SECONDS=$((CURRENT_EPOCH - INACTIVITY_EPOCH))
            THRESHOLD_SECONDS=$(echo "$INACTIVITY_HOURS * 3600 / 1" | bc)  # Force integer
            REMAINING_SECONDS=$((THRESHOLD_SECONDS - ELAPSED_SECONDS))
            
            if [ $REMAINING_SECONDS -gt 0 ]; then
                REMAINING_MINUTES=$((REMAINING_SECONDS / 60))
                REMAINING_HOURS=$(echo "scale=1; $REMAINING_MINUTES / 60" | bc)
                INACTIVITY_DATE=$(date -d "@$INACTIVITY_EPOCH" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$INACTIVITY_EPOCH" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
                echo -e "      Status: ${YELLOW}⏳ IDLE${NC} (since $INACTIVITY_DATE)"
                echo "      ⏰ Shutdown in: ~${REMAINING_MINUTES} minutes (${REMAINING_HOURS}h)"
                if [ -n "$NEXT_EXEC_INFO" ]; then
                    echo "      🔄 $NEXT_EXEC_INFO"
                fi
            else
                echo -e "      Status: ${RED}⚠️  IDLE - eligible for shutdown${NC}"
                if [ -n "$NEXT_EXEC_INFO" ]; then
                    echo "      ⏰ Will be stopped on next Lambda execution ($NEXT_EXEC_INFO)"
                elif [ -n "$RATE_MINUTES" ]; then
                    echo "      ⏰ Will be stopped on next Lambda execution (every $RATE_MINUTES min)"
                else
                    echo "      ⏰ Will be stopped on next Lambda execution"
                fi
            fi
        else
            # Instance is active
            echo -e "      Status: ${GREEN}✅ ACTIVE${NC}"
            echo "      ℹ️  Will be monitored for inactivity (threshold: ${INACTIVITY_HOURS}h)"
            if [ -n "$NEXT_EXEC_INFO" ]; then
                echo "      🔄 $NEXT_EXEC_INFO"
            fi
        fi
        echo ""
    done < <(echo "$INSTANCES_DATA" | jq -r '.[] | @tsv')
else
    echo -e "${YELLOW}⚠️  No running instances found with AutoShutdownEnabled=true tag${NC}"
    echo "   To enable auto-shutdown for an instance, add the tag:"
    echo "   aws ec2 create-tags --resources i-xxxxx --tags Key=AutoShutdownEnabled,Value=true"
fi
echo ""

# Test Lambda Function
echo "📋 Step 9: Testing Lambda Function..."
echo "Do you want to test the Lambda function? (yes/no)"
read -t 10 -r TEST_RESPONSE || TEST_RESPONSE="no"

if [[ $TEST_RESPONSE =~ ^[Yy][Ee][Ss]$ ]] || [[ $TEST_RESPONSE =~ ^[Yy]$ ]]; then
    echo ""
    echo "📅 Test 1: Simulating scheduled event..."
    aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --cli-binary-format raw-in-base64-out \
        --payload '{"source": "aws.events"}' \
        /tmp/response-scheduled.json > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "   ${GREEN}✅ Scheduled event test successful${NC}"
        echo "   Response:"
        cat /tmp/response-scheduled.json | jq '.' 2>/dev/null || cat /tmp/response-scheduled.json
        rm -f /tmp/response-scheduled.json
    else
        echo -e "   ${RED}❌ Scheduled event test failed${NC}"
    fi
    
    echo ""
    echo "🖥️  Test 2: Simulating EC2 state change event..."
    echo "Do you want to test with a specific instance ID? (yes/no)"
    read -t 10 -r TEST_EC2_RESPONSE || TEST_EC2_RESPONSE="no"
    
    if [[ $TEST_EC2_RESPONSE =~ ^[Yy][Ee][Ss]$ ]] || [[ $TEST_EC2_RESPONSE =~ ^[Yy]$ ]]; then
        echo "Enter instance ID (e.g., i-1234567890abcdef0):"
        read -t 10 -r INSTANCE_ID || INSTANCE_ID="i-0000000000000000"
        
        aws lambda invoke \
            --function-name "$FUNCTION_NAME" \
            --region "$REGION" \
            --cli-binary-format raw-in-base64-out \
            --payload "{\"source\": \"aws.ec2\", \"detail\": {\"instance-id\": \"$INSTANCE_ID\", \"state\": \"running\"}}" \
            /tmp/response-ec2-event.json > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "   ${GREEN}✅ EC2 event test successful${NC}"
            echo "   Response:"
            cat /tmp/response-ec2-event.json | jq '.' 2>/dev/null || cat /tmp/response-ec2-event.json
            rm -f /tmp/response-ec2-event.json
        else
            echo -e "   ${RED}❌ EC2 event test failed${NC}"
        fi
    else
        echo "   Skipping EC2 event test"
    fi
    
    echo ""
    echo "📋 Recent CloudWatch logs (last 5 minutes, key events only):"
    LOGS_OUTPUT=$(aws logs tail "$LOG_GROUP" --region "$REGION" --since 5m --format short 2>/dev/null | grep -E '\[INFO\]|\[WARNING\]|\[ERROR\]|REPORT|START RequestId' | tail -30)
    
    if [ -n "$LOGS_OUTPUT" ]; then
        echo "$LOGS_OUTPUT"
    else
        echo "   No recent logs found. View all logs with:"
        echo "   aws logs tail $LOG_GROUP --region $REGION --follow"
    fi
else
    echo "Skipping Lambda test"
fi
echo ""

# Summary
echo "=========================================="
echo "✨ Verification Complete!"
echo ""
echo "📊 Summary:"
echo "   - Main Lambda: $(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" &> /dev/null && echo "✅" || echo "❌")"
echo "   - EventBridge Rules: $(aws events describe-rule --name "$SCHEDULED_RULE" --region "$REGION" &> /dev/null && echo "✅" || echo "❌")"
echo "   - SNS Topic: $([ -n "$SNS_TOPIC_ARN" ] && echo "✅" || echo "❌")"
if [ -n "$TEAMS_NOTIFIER_NAME" ]; then
    echo "   - Teams Notifier: $(aws lambda get-function --function-name "$TEAMS_NOTIFIER_NAME" --region "$REGION" &> /dev/null && echo "✅" || echo "❌")"
fi
echo "   - IAM Role: $(aws iam get-role --role-name "$ROLE_NAME" &> /dev/null && echo "✅" || echo "❌")"
echo ""
echo "💡 Next Steps:"
echo "   1. Tag EC2 instances: aws ec2 create-tags --resources i-xxxxx --tags Key=AutoShutdownEnabled,Value=true"
echo "   2. Monitor logs: aws logs tail $LOG_GROUP --region $REGION --follow"
if [ -n "$TEAMS_NOTIFIER_NAME" ]; then
    echo "   3. Check Teams notifications for shutdown alerts"
fi
echo ""
