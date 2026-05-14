# Phase 2: Stop/Start Scripts

**Status:** Pending  
**Priority:** Medium

## Overview

Create convenience scripts to stop/start the cluster safely.

## Implementation

### 1. Create `scripts/cluster-stop.sh`

```bash
#!/bin/bash
set -e

REGION="us-west-1"
TAG_KEY="Project"
TAG_VALUE="nomad-k8s"

echo "Finding EC2 instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "No running instances found."
  exit 0
fi

echo "Stopping instances: $INSTANCE_IDS"
aws ec2 stop-instances --region $REGION --instance-ids $INSTANCE_IDS

echo "Waiting for instances to stop..."
aws ec2 wait instance-stopped --region $REGION --instance-ids $INSTANCE_IDS

echo "All instances stopped."
```

### 2. Create `scripts/cluster-start.sh`

```bash
#!/bin/bash
set -e

REGION="us-west-1"
TAG_KEY="Project"
TAG_VALUE="nomad-k8s"

echo "Finding EC2 instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" "Name=instance-state-name,Values=stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "No stopped instances found."
  exit 0
fi

echo "Starting instances: $INSTANCE_IDS"
aws ec2 start-instances --region $REGION --instance-ids $INSTANCE_IDS

echo "Waiting for instances to start..."
aws ec2 wait instance-running --region $REGION --instance-ids $INSTANCE_IDS

echo "All instances started. Waiting for services..."
sleep 30

# Get first instance IP for health checks
FIRST_IP=$(aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "Checking Consul health..."
until curl -s "http://$FIRST_IP:8500/v1/status/leader" > /dev/null 2>&1; do
  echo "Waiting for Consul..."
  sleep 5
done

echo "Cluster ready!"
echo "Consul: http://$FIRST_IP:8500"
echo "Nomad:  http://$FIRST_IP:4646"
echo "Vault:  https://$FIRST_IP:8200"
```

## Validation

- [ ] Scripts executable: `chmod +x scripts/cluster-*.sh`
- [ ] Stop script stops all 3 instances
- [ ] Start script starts and waits for health
- [ ] IPs remain same after start (verify EIPs working)
