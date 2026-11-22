# Schedules `terraform destroy` for the demo stack so a forgotten session cannot keep running.
# Usage: pwsh scripts/kill-timer.ps1 [-Minutes 90]
# Creates a one-shot Windows scheduled task "sentinel-kill-timer". Cancel with:
#   Unregister-ScheduledTask -TaskName sentinel-kill-timer -Confirm:$false
param([int]$Minutes = 90)

$repo = Split-Path -Parent $PSScriptRoot
$demo = Join-Path $repo 'infra\demo'
$log = Join-Path $repo 'docs\proof\kill-timer-destroy.log'
$cmd = "`$env:AWS_PROFILE='sentinel'; `$env:AWS_REGION='ap-southeast-2'; Set-Location '$demo'; " +
       "terraform destroy -auto-approve -input=false -no-color *> '$log'; " +
       "& '$repo\scripts\verify-teardown.ps1' *>> '$log'"

$when = (Get-Date).AddMinutes($Minutes)
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -Command `"$cmd`""
$trigger = New-ScheduledTaskTrigger -Once -At $when
Register-ScheduledTask -TaskName 'sentinel-kill-timer' -Action $action -Trigger $trigger -Force | Out-Null
Write-Host "Kill timer armed: terraform destroy will run at $when ($Minutes min from now)."
