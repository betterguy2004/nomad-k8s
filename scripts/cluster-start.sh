#!/bin/bash
set -e

REGION="${AWS_REGION:-us-west-1}"
TAG_KEY="Project"
TAG_VALUE="nomad-k8s"

echo "Finding stopped EC2 instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" "Name=instance-state-name,Values=stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "No stopped instances found."
  exit 0
fi

echo "Starting instances: $INSTANCE_IDS"
aws ec2 start-instances --region "$REGION" --instance-ids $INSTANCE_IDS

echo "Waiting for instances to start..."
aws ec2 wait instance-running --region "$REGION" --instance-ids $INSTANCE_IDS

echo "Instances running. Waiting for services to initialize..."
sleep 30

# Get first instance EIP
FIRST_IP=$(aws ec2 describe-addresses \
  --region "$REGION" \
  --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" \
  --query "Addresses[0].PublicIp" \
  --output text 2>/dev/null || \
  aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo "Checking Consul health..."
for i in {1..12}; do
  if curl -s "http://$FIRST_IP:8500/v1/status/leader" > /dev/null 2>&1; then
    echo "Consul is healthy!"
    break
  fi
  echo "Waiting for Consul... ($i/12)"
  sleep 10
done

echo ""
echo "========================================="
echo "Cluster ready!"
echo "========================================="
echo "Consul: http://$FIRST_IP:8500"
echo "Nomad:  http://$FIRST_IP:4646"
echo "Vault:  https://$FIRST_IP:8200"
echo "SSH:    ssh -i ~/.ssh/nomad-k8s-dev ubuntu@$FIRST_IP"
echo "========================================="
