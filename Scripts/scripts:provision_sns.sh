
#!/bin/bash
# provision_sns.sh — creates SNS topics and subscribes email
# Usage: bash scripts/provision_sns.sh your-email@company.com

EMAIL=${1:?"Usage: $0 <email-address>"}
REGION="us-east-1"

echo "Creating SNS topics..."

WARN_ARN=$(aws sns create-topic --name disk-monitoring-warning --region $REGION --query 'TopicArn' --output text)
CRIT_ARN=$(aws sns create-topic --name disk-monitoring-critical --region $REGION --query 'TopicArn' --output text)
EMRG_ARN=$(aws sns create-topic --name disk-monitoring-emergency --region $REGION --query 'TopicArn' --output text)

echo "  WARNING:   $WARN_ARN"
echo "  CRITICAL:  $CRIT_ARN"
echo "  EMERGENCY: $EMRG_ARN"

echo ""
echo "Subscribing $EMAIL to all topics..."

aws sns subscribe --topic-arn $WARN_ARN --protocol email --notification-endpoint $EMAIL --region $REGION
aws sns subscribe --topic-arn $CRIT_ARN --protocol email --notification-endpoint $EMAIL --region $REGION
aws sns subscribe --topic-arn $EMRG_ARN --protocol email --notification-endpoint $EMAIL --region $REGION

echo ""
echo "Done. Check your inbox and confirm all 3 subscription emails."
echo ""
echo "Export these for create_alarms.sh:"
echo "  export SNS_WARNING_ARN=$WARN_ARN"
echo "  export SNS_CRITICAL_ARN=$CRIT_ARN"
echo "  export SNS_EMERGENCY_ARN=$EMRG_ARN"

