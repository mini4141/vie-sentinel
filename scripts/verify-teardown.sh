#!/usr/bin/env bash
# Teardown check for Linux runners (and Git Bash): lists anything billable the demo stack could leave behind.
# Usage: scripts/verify-teardown.sh   (uses AWS credentials from the environment or AWS_PROFILE)
# Exit 0 = clean, exit 1 = leftovers or a query failed. Read-only; creates and deletes nothing.
set -u

REGION="${AWS_REGION:-ap-southeast-2}"
LEFT=0

check() { # name, then the aws command
  local name="$1"
  shift
  local out rc items count
  out=$("$@" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "[ERROR] $name: query failed: $(echo "$out" | tr '\n' ' ' | sed -E 's/[0-9]{12}/<account-id>/g' | cut -c1-200)"
    LEFT=$((LEFT + 1))
    return
  fi
  items=$(echo "$out" | tr '\t' '\n' | sed '/^$/d;/^None$/d')
  if [ -z "$items" ]; then
    echo "[ OK  ] $name: 0"
  else
    count=$(echo "$items" | wc -l | tr -d ' ')
    echo "[LEFT ] $name: $count -> $(echo "$items" | sed -E 's/[0-9]{12}/<account-id>/g' | tr '\n' ' ')"
    LEFT=$((LEFT + count))
  fi
}

A=(--region "$REGION" --output text)

echo "verify-teardown $(date -u +%Y-%m-%dT%H:%M:%SZ) region=$REGION"
check "load balancers"         aws elbv2 describe-load-balancers "${A[@]}" --query 'LoadBalancers[].LoadBalancerName'
check "target groups"          aws elbv2 describe-target-groups "${A[@]}" --query 'TargetGroups[].TargetGroupName'
check "RDS instances"          aws rds describe-db-instances "${A[@]}" --query 'DBInstances[].DBInstanceIdentifier'
check "RDS snapshots"          aws rds describe-db-snapshots "${A[@]}" --query 'DBSnapshots[].DBSnapshotIdentifier'
check "NAT gateways"           aws ec2 describe-nat-gateways "${A[@]}" --filter 'Name=state,Values=pending,available,deleting' --query 'NatGateways[].NatGatewayId'
check "Elastic IPs"            aws ec2 describe-addresses "${A[@]}" --query 'Addresses[].AllocationId'
# ECS clusters must be zero, which also rules out running tasks and services.
check "ECS clusters"           aws ecs list-clusters "${A[@]}" --query 'clusterArns[]'
check "ENIs (Project=sentinel)" aws ec2 describe-network-interfaces "${A[@]}" --filters 'Name=tag:Project,Values=sentinel' --query 'NetworkInterfaces[].NetworkInterfaceId'
check "VPCs (Project=sentinel)" aws ec2 describe-vpcs "${A[@]}" --filters 'Name=tag:Project,Values=sentinel' --query 'Vpcs[].VpcId'
check "SQS queues (sentinel-*)" aws sqs list-queues "${A[@]}" --queue-name-prefix sentinel --query 'QueueUrls[]'
check "Secrets (sentinel/)"    aws secretsmanager list-secrets "${A[@]}" --filters Key=name,Values=sentinel/ --query 'SecretList[].Name'

if [ "$LEFT" -eq 0 ]; then
  echo "RESULT: CLEAN - zero leftover billable resources."
  exit 0
fi
echo "::error::teardown check found $LEFT leftover item(s) or failed queries - delete them and re-run"
echo "RESULT: $LEFT leftover item(s) - delete them and re-run."
exit 1
