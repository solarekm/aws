import boto3
import datetime
import time
import os
import logging
import json
from botocore.exceptions import BotoCoreError, ClientError

# Logger configuration
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Configurable parameters via environment variables
CPU_THRESHOLD = float(os.environ.get('CPU_THRESHOLD', '10'))  # %
NETWORK_THRESHOLD = float(os.environ.get('NETWORK_THRESHOLD', '100000'))  # bytes
DISK_THRESHOLD = float(os.environ.get('DISK_THRESHOLD', '1000000'))  # bytes
INACTIVITY_HOURS = float(os.environ.get('INACTIVITY_HOURS', '3'))  # hours
METRIC_PERIOD = int(os.environ.get('METRIC_PERIOD', '300'))  # seconds
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')  # SNS topic for notifications

ec2_client = boto3.client('ec2')
cloudwatch = boto3.client('cloudwatch')
sns_client = boto3.client('sns')

def lambda_handler(event, context):
    """
    Main Lambda handler for EC2 auto shutdown functionality.
    Handles both scheduled events and EC2 state change events.
    """
    try:
        # Log the incoming event for debugging
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Determine event type and handle accordingly
        event_source = event.get('source', 'manual')
        
        if event_source == 'aws.ec2':
            # Handle EC2 state change event
            instance_id = event['detail']['instance-id']
            state = event['detail']['state']
            logger.info(f"Processing EC2 state change event for instance {instance_id}, state: {state}")
            
            if state == 'running':
                # Process only the specific instance that just started
                process_single_instance(instance_id)
            else:
                logger.info(f"Ignoring state change to {state} for instance {instance_id}")
        else:
            # Handle scheduled event - process all running instances
            logger.info("Processing scheduled check for all instances")
            process_all_instances()
            
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'EC2 auto shutdown check completed successfully',
                'event_source': event_source
            })
        }
    
    except Exception as e:
        logger.error(f"Unexpected error in lambda_handler: {str(e)}")
        raise

def process_all_instances():
    """Process all running EC2 instances for auto shutdown."""
    try:
        # Get all running instances
        instances = ec2_client.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
        )
        
        instance_count = 0
        processed_count = 0
        
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                instance_count += 1
                instance_id = instance['InstanceId']
                
                if process_instance(instance):
                    processed_count += 1
        
        logger.info(f"Processed {processed_count} out of {instance_count} running instances")
    
    except (BotoCoreError, ClientError) as e:
        logger.error(f"Error retrieving EC2 instances: {str(e)}")
        raise

def process_single_instance(instance_id):
    """Process a single EC2 instance by ID."""
    try:
        # Get specific instance details
        instances = ec2_client.describe_instances(InstanceIds=[instance_id])
        
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                if instance['State']['Name'] == 'running':
                    process_instance(instance)
                    logger.info(f"Processed newly running instance {instance_id}")
                else:
                    logger.info(f"Instance {instance_id} is not in running state, skipping")
    
    except (BotoCoreError, ClientError) as e:
        logger.error(f"Error processing instance {instance_id}: {str(e)}")

def process_instance(instance):
    """Process a single instance for auto shutdown logic."""
    instance_id = instance['InstanceId']
    
    try:
        # Check if auto shutdown is enabled for this instance
        auto_shutdown_enabled = False
        for tag in instance.get('Tags', []):
            if tag['Key'] == 'AutoShutdownEnabled' and tag['Value'].lower() == 'true':
                auto_shutdown_enabled = True
                break
        
        if not auto_shutdown_enabled:
            logger.debug(f"Auto shutdown not enabled for instance {instance_id}")
            return False
            
        logger.info(f"Processing instance {instance_id} with auto shutdown enabled")
        
        # Check idle metrics
        is_idle = check_if_instance_idle(instance_id)
        
        # Get or set inactivity start timestamp
        inactivity_start = get_inactivity_start(instance_id, is_idle)
        
        # Update LastActivityCheck tag
        update_activity_check_tag(instance_id)
        
        # If instance is idle for more than specified time, stop it
        if is_idle and inactivity_start:
            idle_time = (datetime.datetime.utcnow() - 
                        datetime.datetime.utcfromtimestamp(float(inactivity_start))).total_seconds() / 3600
            
            if idle_time >= INACTIVITY_HOURS:
                logger.info(f"Stopping instance {instance_id} after {idle_time:.2f} hours of inactivity")
                
                # Get instance name from tags
                instance_name = 'N/A'
                for tag in instance.get('Tags', []):
                    if tag['Key'] == 'Name':
                        instance_name = tag['Value']
                        break
                
                # Get metrics for notification
                metrics_data = get_metrics_for_notification(instance_id)
                
                # Stop the instance
                ec2_client.stop_instances(InstanceIds=[instance_id])
                
                # Clear InactivityStart tag after stopping
                ec2_client.delete_tags(
                    Resources=[instance_id],
                    Tags=[{'Key': 'InactivityStart'}]
                )
                
                # Send notification via SNS
                send_shutdown_notification(
                    instance_id=instance_id,
                    instance_name=instance_name,
                    idle_time_hours=idle_time,
                    metrics_data=metrics_data
                )
                
                return True
        
        return True
    
    except (BotoCoreError, ClientError) as e:
        logger.error(f"Error processing instance {instance_id}: {str(e)}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error processing instance {instance_id}: {str(e)}")
        return False

def get_metrics_for_notification(instance_id):
    """Get average metrics for the notification message."""
    try:
        end_time = datetime.datetime.utcnow()
        start_time = end_time - datetime.timedelta(hours=INACTIVITY_HOURS)
        
        # Get CPU average
        cpu_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='CPUUtilization',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        cpu_avg = 'N/A'
        if cpu_response['Datapoints']:
            cpu_avg = sum(dp['Average'] for dp in cpu_response['Datapoints']) / len(cpu_response['Datapoints'])
            cpu_avg = f"{cpu_avg:.2f}"
        
        # Get Network average
        network_in = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='NetworkIn',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        network_out = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='NetworkOut',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        network_avg = 'N/A'
        network_datapoints = network_in['Datapoints'] + network_out['Datapoints']
        if network_datapoints:
            network_avg = sum(dp['Average'] for dp in network_datapoints) / len(network_datapoints)
            network_avg = f"{network_avg:.0f}"
        
        # Determine disk type
        disk_type = 'None'
        ebs_read = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='EBSReadBytes',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        disk_read = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='DiskReadBytes',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        if ebs_read['Datapoints']:
            disk_type = 'EBS'
        elif disk_read['Datapoints']:
            disk_type = 'Instance Store'
        
        return {
            'cpu_avg': cpu_avg,
            'network_avg': network_avg,
            'disk_type': disk_type
        }
    except Exception as e:
        logger.warning(f"Error getting metrics for notification: {str(e)}")
        return {
            'cpu_avg': 'N/A',
            'network_avg': 'N/A',
            'disk_type': 'N/A'
        }

def send_shutdown_notification(instance_id, instance_name, idle_time_hours, metrics_data):
    """Send notification to SNS topic about instance shutdown."""
    if not SNS_TOPIC_ARN:
        logger.debug("SNS_TOPIC_ARN not configured, skipping notification")
        return
    
    try:
        message = {
            'instance_id': instance_id,
            'instance_name': instance_name,
            'idle_time_hours': idle_time_hours,
            'cpu_avg': metrics_data.get('cpu_avg', 'N/A'),
            'network_avg': metrics_data.get('network_avg', 'N/A'),
            'disk_type': metrics_data.get('disk_type', 'N/A'),
            'timestamp': datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
        }
        
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f'EC2 Instance Shutdown: {instance_name} ({instance_id})',
            Message=json.dumps(message, indent=2)
        )
        
        logger.info(f"Sent shutdown notification for instance {instance_id} to SNS")
    except Exception as e:
        logger.error(f"Error sending SNS notification: {str(e)}")

def check_if_instance_idle(instance_id):
    """Check if an EC2 instance is idle based on CloudWatch metrics."""
    try:
        # Check metrics from the last INACTIVITY_HOURS period
        end_time = datetime.datetime.utcnow()
        start_time = end_time - datetime.timedelta(hours=INACTIVITY_HOURS)
        
        # Check average CPU usage
        cpu_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='CPUUtilization',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        # Check network activity
        network_in = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='NetworkIn',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        network_out = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='NetworkOut',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        # Check disk activity - try both EBS and Instance Store metrics
        # EBS metrics: EBSReadBytes, EBSWriteBytes
        # Instance Store metrics: DiskReadBytes, DiskWriteBytes
        
        ebs_read = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='EBSReadBytes',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        ebs_write = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='EBSWriteBytes',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        disk_read = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='DiskReadBytes',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        disk_write = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='DiskWriteBytes',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=METRIC_PERIOD,
            Statistics=['Average']
        )
        
        # Analyze data - instance is idle if all metrics are below thresholds
        cpu_idle = all(datapoint['Average'] < CPU_THRESHOLD for datapoint in cpu_response['Datapoints'])
        net_idle = all(datapoint['Average'] < NETWORK_THRESHOLD for datapoint in network_in['Datapoints'] + network_out['Datapoints'])
        
        # Check disk metrics - use EBS OR Instance Store (not both, as instance has one type)
        ebs_datapoints = ebs_read['Datapoints'] + ebs_write['Datapoints']
        disk_datapoints = disk_read['Datapoints'] + disk_write['Datapoints']
        
        if ebs_datapoints:
            # Instance has EBS volumes
            disk_idle = all(datapoint['Average'] < DISK_THRESHOLD for datapoint in ebs_datapoints)
            ebs_values = [f"{dp['Average']:.0f}" for dp in ebs_datapoints]
            logger.debug(f"Instance {instance_id} using EBS metrics for disk check - values: {ebs_values}, threshold: {DISK_THRESHOLD}")
        elif disk_datapoints:
            # Instance has Instance Store
            disk_idle = all(datapoint['Average'] < DISK_THRESHOLD for datapoint in disk_datapoints)
            logger.debug(f"Instance {instance_id} using Instance Store metrics for disk check")
        else:
            # No disk metrics available
            disk_idle = True  # Skip disk check if no disk data available
            logger.debug(f"Instance {instance_id} has no disk metrics available, skipping disk check")
        
        # Check if we have enough data points (CPU and Network are required)
        total_datapoints = len(cpu_response['Datapoints']) + len(network_in['Datapoints']) + len(network_out['Datapoints'])
        if total_datapoints == 0:
            logger.warning(f"No metric data available for instance {instance_id}, considering as active")
            return False
        
        is_idle = cpu_idle and net_idle and disk_idle
        logger.debug(f"Instance {instance_id} idle check - CPU: {cpu_idle}, Network: {net_idle}, Disk: {disk_idle}, Overall: {is_idle}")
        
        return is_idle
    
    except (BotoCoreError, ClientError) as e:
        logger.error(f"Error checking metrics for instance {instance_id}: {str(e)}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error checking instance {instance_id}: {str(e)}")
        return False

def get_inactivity_start(instance_id, is_idle):
    """Get or manage the inactivity start timestamp for an instance."""
    try:
        # Get current inactivity start timestamp
        response = ec2_client.describe_tags(
            Filters=[
                {'Name': 'resource-id', 'Values': [instance_id]},
                {'Name': 'key', 'Values': ['InactivityStart']}
            ]
        )
        
        inactivity_start = None
        if response['Tags']:
            inactivity_start = response['Tags'][0]['Value']
        
        # If instance is idle and doesn't have timestamp yet, set it
        if is_idle and not inactivity_start:
            current_time = str(time.time())
            ec2_client.create_tags(
                Resources=[instance_id],
                Tags=[{'Key': 'InactivityStart', 'Value': current_time}]
            )
            inactivity_start = current_time
            logger.info(f"Set inactivity start timestamp for instance {instance_id}")
        
        # If instance is not idle but has timestamp, remove it
        elif not is_idle and inactivity_start:
            ec2_client.delete_tags(
                Resources=[instance_id],
                Tags=[{'Key': 'InactivityStart'}]
            )
            inactivity_start = None
            logger.info(f"Cleared inactivity start timestamp for instance {instance_id}")
        
        return inactivity_start
    
    except (BotoCoreError, ClientError) as e:
        logger.error(f"Error managing inactivity timestamp for instance {instance_id}: {str(e)}")
        return None
    except Exception as e:
        logger.error(f"Unexpected error managing timestamp for instance {instance_id}: {str(e)}")
        return None

def update_activity_check_tag(instance_id):
    """Update the last activity check timestamp for an instance."""
    try:
        # Update last check timestamp
        current_time = str(time.time())
        ec2_client.create_tags(
            Resources=[instance_id],
            Tags=[{'Key': 'LastActivityCheck', 'Value': current_time}]
        )
    except (BotoCoreError, ClientError) as e:
        logger.error(f"Error updating activity check tag for instance {instance_id}: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error updating activity tag for instance {instance_id}: {str(e)}")
