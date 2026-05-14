#!/bin/bash
set -e

REGION="${AWS_REGION:-us-west-1}"
TAG_KEY="Project"
TAG_VALUE="nomad-k8s"

echo "Finding running EC2 instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "No running instances found."
  exit 0
fi

echo "Stopping instances: $INSTANCE_IDS"
aws ec2 stop-instances --region "$REGION" --instance-ids $INSTANCE_IDS

echo "Waiting for instances to stop..."
aws ec2 wait instance-stopped --region "$REGION" --instance-ids $INSTANCE_IDS

echo "All instances stopped."
echo "Note: Elastic IPs will incur ~\$0.005/hour while instances are stopped."
