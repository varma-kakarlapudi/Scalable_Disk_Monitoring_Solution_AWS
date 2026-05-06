
#!/bin/bash
# create_alarms.sh — creates CW alarms for all instances reporting metrics
# Run after agents are pushing metrics (wait ~5 min after deploy)

NAMESPACE="Custom/DiskMonitoring"
REGION="us-east-1"

# need these exported (from provision_sns.sh output)
: "${SNS_WARNING_ARN:?Set SNS_WARNING_ARN first}"
: "${SNS_CRITICAL_ARN:?Set SNS_CRITICAL_ARN first}"
: "${SNS_EMERGENCY_ARN:?Set SNS_EMERGENCY_ARN first}"

echo "Discovering instances reporting metrics..."
INSTANCES=$(aws cloudwatch list-metrics --namespace "$NAMESPACE" \
  --metric-name "disk_used_percent" --region $REGION \
  --query "Metrics[?Dimensions[?Name=='path'&&Value=='/']].Dimensions[?Name=='InstanceId'].Value|[][]" \
  --output text | sort -u)

for INSTANCE_ID in $INSTANCES; do
  echo ""
  echo "Creating alarms for $INSTANCE_ID..."

  # WARNING at 75%
  aws cloudwatch put-metric-alarm \
    --alarm-name "disk-warn-${INSTANCE_ID}-root" \
    --namespace "$NAMESPACE" \
    --metric-name "disk_used_percent" \
    --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=path,Value=/ \
    --statistic Average --period 300 \
    --evaluation-periods 3 --datapoints-to-alarm 2 \
    --threshold 75 --comparison-operator GreaterThanOrEqualToThreshold \
    --alarm-actions $SNS_WARNING_ARN \
    --treat-missing-data breaching \
    --region $REGION

  # CRITICAL at 90%
  aws cloudwatch put-metric-alarm \
    --alarm-name "disk-crit-${INSTANCE_ID}-root" \
    --namespace "$NAMESPACE" \
    --metric-name "disk_used_percent" \
    --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=path,Value=/ \
    --statistic Average --period 300 \
    --evaluation-periods 2 --datapoints-to-alarm 2 \
    --threshold 90 --comparison-operator GreaterThanOrEqualToThreshold \
    --alarm-actions $SNS_CRITICAL_ARN \
    --treat-missing-data breaching \
    --region $REGION

  # EMERGENCY at 95%
  aws cloudwatch put-metric-alarm \
    --alarm-name "disk-emrg-${INSTANCE_ID}-root" \
    --namespace "$NAMESPACE" \
    --metric-name "disk_used_percent" \
    --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=path,Value=/ \
    --statistic Average --period 60 \
    --evaluation-periods 1 --datapoints-to-alarm 1 \
    --threshold 95 --comparison-operator GreaterThanOrEqualToThreshold \
    --alarm-actions $SNS_EMERGENCY_ARN \
    --treat-missing-data breaching \
    --region $REGION

  echo "  done: 3 alarms for $INSTANCE_ID"
done

echo ""
echo "All alarms created. Verify:"
echo "  aws cloudwatch describe-alarms --alarm-name-prefix disk- --region $REGION --output table"

