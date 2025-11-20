import json
import os
import urllib3
from datetime import datetime

# Initialize HTTP client
http = urllib3.PoolManager()

# Get Teams webhook URLs from environment variable (JSON list)
TEAMS_WEBHOOK_URLS = json.loads(os.environ.get('TEAMS_WEBHOOK_URLS', '[]'))

def lambda_handler(event, context):
    """
    Lambda function to send notifications to Microsoft Teams when EC2 instances are shut down.
    Triggered by SNS messages from the main auto-shutdown Lambda.
    """
    try:
        # Parse SNS message
        for record in event['Records']:
            if record['EventSource'] == 'aws:sns':
                message = json.loads(record['Sns']['Message'])
                
                # Send notification to all configured Teams webhooks
                if TEAMS_WEBHOOK_URLS:
                    for webhook_url in TEAMS_WEBHOOK_URLS:
                        send_teams_notification(message, webhook_url)
                else:
                    print("Warning: TEAMS_WEBHOOK_URLS not configured, skipping Teams notification")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Notifications sent successfully')
        }
    
    except Exception as e:
        print(f"Error sending notification: {str(e)}")
        raise

def send_teams_notification(message, webhook_url):
    """
    Send a formatted notification to Microsoft Teams using Adaptive Cards.
    """
    instance_id = message.get('instance_id', 'Unknown')
    instance_name = message.get('instance_name', 'N/A')
    idle_time = message.get('idle_time_hours', 0)
    cpu_avg = message.get('cpu_avg', 'N/A')
    network_avg = message.get('network_avg', 'N/A')
    disk_type = message.get('disk_type', 'N/A')
    timestamp = message.get('timestamp', datetime.utcnow().isoformat())
    
    # Create Adaptive Card for Teams
    adaptive_card = {
        "type": "message",
        "attachments": [
            {
                "contentType": "application/vnd.microsoft.card.adaptive",
                "contentUrl": None,
                "content": {
                    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                    "type": "AdaptiveCard",
                    "version": "1.4",
                    "body": [
                        {
                            "type": "Container",
                            "style": "attention",
                            "items": [
                                {
                                    "type": "ColumnSet",
                                    "columns": [
                                        {
                                            "type": "Column",
                                            "width": "auto",
                                            "items": [
                                                {
                                                    "type": "TextBlock",
                                                    "text": "🔴",
                                                    "size": "ExtraLarge"
                                                }
                                            ]
                                        },
                                        {
                                            "type": "Column",
                                            "width": "stretch",
                                            "items": [
                                                {
                                                    "type": "TextBlock",
                                                    "text": "EC2 Instance Shutdown",
                                                    "weight": "Bolder",
                                                    "size": "Large"
                                                },
                                                {
                                                    "type": "TextBlock",
                                                    "text": "Automatic shutdown due to inactivity",
                                                    "isSubtle": True,
                                                    "spacing": "None"
                                                }
                                            ]
                                        }
                                    ]
                                }
                            ]
                        },
                        {
                            "type": "FactSet",
                            "facts": [
                                {
                                    "title": "Name:",
                                    "value": instance_name
                                },
                                {
                                    "title": "Instance ID:",
                                    "value": instance_id
                                },
                                {
                                    "title": "Idle Time:",
                                    "value": f"{idle_time:.2f} hours"
                                },
                                {
                                    "title": "Avg CPU:",
                                    "value": f"{cpu_avg}%" if cpu_avg != 'N/A' else 'N/A'
                                },
                                {
                                    "title": "Avg Network:",
                                    "value": f"{network_avg} bytes" if network_avg != 'N/A' else 'N/A'
                                },
                                {
                                    "title": "Disk Type:",
                                    "value": disk_type
                                },
                                {
                                    "title": "Timestamp:",
                                    "value": timestamp
                                }
                            ]
                        }
                    ]
                }
            }
        ]
    }
    
    # Send to Teams webhook
    encoded_data = json.dumps(adaptive_card).encode('utf-8')
    
    response = http.request(
        'POST',
        webhook_url,
        body=encoded_data,
        headers={'Content-Type': 'application/json'}
    )
    
    if response.status == 200:
        print(f"Successfully sent Teams notification for instance {instance_id} to {webhook_url[:50]}...")
    else:
        print(f"Failed to send Teams notification to {webhook_url[:50]}... Status: {response.status}, Response: {response.data}")
