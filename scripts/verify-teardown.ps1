# Verifies that nothing billable from the demo stack is left in ap-southeast-2.
# Usage: pwsh scripts/verify-teardown.ps1   (exit 0 = clean, exit 1 = leftovers)
$ErrorActionPreference = 'Continue'
$AwsProfile = 'sentinel'
$Region = 'ap-southeast-2'
$leftovers = 0

function Check($name, [scriptblock]$query) {
    $out = (& $query 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("[ERROR] {0}: query failed: {1}" -f $name, $out)
        $script:leftovers++
        return
    }
    $items = @($out -split '\s+' | Where-Object { $_ -and $_ -ne 'None' })
    if ($items.Count -eq 0) {
        Write-Host ("[ OK  ] {0}: 0" -f $name)
    } else {
        Write-Host ("[LEFT ] {0}: {1} -> {2}" -f $name, $items.Count, ($items -join ', '))
        $script:leftovers += $items.Count
    }
}

$ident = aws sts get-caller-identity --profile $AwsProfile --query Arn --output text
Write-Host "verify-teardown $(Get-Date -Format u) region=$Region identity=$($ident -replace ':\d{12}:', ':<account-id>:')"

$common = @('--profile', $AwsProfile, '--region', $Region, '--output', 'text')
Check 'load balancers'      { aws elbv2 describe-load-balancers @common --query 'LoadBalancers[].LoadBalancerName' }
Check 'target groups'       { aws elbv2 describe-target-groups @common --query 'TargetGroups[].TargetGroupName' }
Check 'RDS instances'       { aws rds describe-db-instances @common --query 'DBInstances[].DBInstanceIdentifier' }
Check 'RDS snapshots'       { aws rds describe-db-snapshots @common --query 'DBSnapshots[].DBSnapshotIdentifier' }
Check 'NAT gateways'        { aws ec2 describe-nat-gateways @common --filter 'Name=state,Values=pending,available,deleting' --query 'NatGateways[].NatGatewayId' }
Check 'Elastic IPs'         { aws ec2 describe-addresses @common --query 'Addresses[].AllocationId' }
Check 'ECS clusters'        { aws ecs list-clusters @common --query 'clusterArns[]' }
Check 'ENIs (Project=sentinel)' { aws ec2 describe-network-interfaces @common --filters 'Name=tag:Project,Values=sentinel' --query 'NetworkInterfaces[].NetworkInterfaceId' }
Check 'VPCs (Project=sentinel)' { aws ec2 describe-vpcs @common --filters 'Name=tag:Project,Values=sentinel' --query 'Vpcs[].VpcId' }
Check 'SQS queues'          { aws sqs list-queues @common --queue-name-prefix sentinel --query 'QueueUrls[]' }
Check 'Secrets (sentinel/)' { aws secretsmanager list-secrets @common --filters Key=name,Values=sentinel/ --query 'SecretList[].Name' }

if ($leftovers -eq 0) {
    Write-Host 'RESULT: CLEAN - zero leftover billable resources.'
    exit 0
}
Write-Host "RESULT: $leftovers leftover item(s) - delete them and re-run."
exit 1
