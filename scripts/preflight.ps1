# Read-only permission preflight: one harmless call per AWS service the Terraform stacks use.
# Usage: powershell -File scripts/preflight.ps1 [-AwsProfile sentinel] [-Region ap-southeast-2]
# Exit 0 = every service reachable, 1 = at least one denial or error. Creates nothing.
param(
    [string]$AwsProfile = 'sentinel',
    [string]$Region = 'ap-southeast-2'
)
$ErrorActionPreference = 'Continue'
$common = @('--profile', $AwsProfile, '--region', $Region, '--output', 'json')

$checks = @(
    @{ Service = 'sts';             Args = @('sts', 'get-caller-identity') },
    @{ Service = 'ec2 (VPC)';       Args = @('ec2', 'describe-vpcs', '--max-items', '1') },
    @{ Service = 'ec2 (AZs)';       Args = @('ec2', 'describe-availability-zones') },
    @{ Service = 'elbv2 (ALB)';     Args = @('elbv2', 'describe-load-balancers', '--page-size', '1') },
    @{ Service = 'ecs';             Args = @('ecs', 'list-clusters', '--max-items', '1') },
    @{ Service = 'rds';             Args = @('rds', 'describe-db-instances', '--max-items', '1') },
    @{ Service = 'sqs';             Args = @('sqs', 'list-queues', '--max-items', '1') },
    @{ Service = 'secretsmanager';  Args = @('secretsmanager', 'list-secrets', '--max-results', '1') },
    @{ Service = 'logs';            Args = @('logs', 'describe-log-groups', '--limit', '1') },
    @{ Service = 'cloudwatch';      Args = @('cloudwatch', 'describe-alarms', '--max-records', '1') },
    @{ Service = 'sns';             Args = @('sns', 'list-topics') },
    @{ Service = 'ecr';             Args = @('ecr', 'describe-repositories', '--max-items', '1') },
    @{ Service = 'iam (global)';    Args = @('iam', 'list-roles', '--max-items', '1') },
    @{ Service = 's3 (state)';      Args = @('s3api', 'list-buckets') },
    @{ Service = 'dynamodb (lock)'; Args = @('dynamodb', 'list-tables', '--max-items', '1') }
)

$rows = foreach ($c in $checks) {
    $out = (& aws @($c.Args) @common 2>&1 | Out-String).Trim()
    $ok = ($LASTEXITCODE -eq 0)
    $detail = ''
    if (-not $ok) {
        $detail = ($out -replace '\s+', ' ')
        $detail = $detail -replace '\d{12}', '<account-id>'
        if ($detail.Length -gt 110) { $detail = $detail.Substring(0, 110) + '...' }
    }
    [pscustomobject]@{ Service = $c.Service; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }); Detail = $detail }
}

Write-Host "preflight profile=$AwsProfile region=$Region $((Get-Date).ToUniversalTime().ToString('u'))"
$rows | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
$failed = @($rows | Where-Object Result -eq 'FAIL').Count
Write-Host ("RESULT: {0} passed, {1} failed" -f ($rows.Count - $failed), $failed)
if ($failed -gt 0) { exit 1 }
exit 0
