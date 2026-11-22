# Proof run against a deployed stack: ALLOW/BLOCK/REVIEW scenarios, smoke test, short k6 load test.
# Usage: powershell -File scripts/proof-run.ps1 -BaseUrl http://<alb-dns>
# The API key is read from Secrets Manager into memory and never printed.
param([Parameter(Mandatory)][string]$BaseUrl)

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
$proof = Join-Path $repo 'docs\proof'
New-Item -ItemType Directory -Force $proof | Out-Null
$BaseUrl = $BaseUrl.TrimEnd('/')

$key = aws secretsmanager get-secret-value --secret-id sentinel/api-key --query SecretString --output text --profile sentinel --region ap-southeast-2
$env:API_KEY = $key

function Post($body) {
    Invoke-RestMethod -Method Post -Uri "$BaseUrl/events" -Headers @{ 'X-API-Key' = $key } -ContentType 'application/json' -Body $body
}
$run = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$now = { (Get-Date).ToUniversalTime().ToString('o') }

$out = Join-Path $proof 'scenarios-aws.txt'
"Scenarios against $BaseUrl at $(& $now)" | Set-Content $out
$allow = Post (@{ idempotencyKey = "s-allow-$run"; userId = "s-u1-$run"; deviceId = "s-d1-$run"; ip = '10.0.0.1'; type = 'INSTALL'; occurredAt = (& $now) } | ConvertTo-Json)
"ALLOW  : $($allow | ConvertTo-Json -Compress)" | Add-Content $out
$review = Post (@{ idempotencyKey = "s-review-$run"; userId = "s-u2-$run"; deviceId = "s-d2-$run"; ip = '10.0.0.1'; type = 'OFFER_COMPLETED'; playSeconds = 2; occurredAt = (& $now) } | ConvertTo-Json)
"REVIEW : $($review | ConvertTo-Json -Compress)" | Add-Content $out
$block = $null
1..7 | ForEach-Object {
    $block = Post (@{ idempotencyKey = "s-block-$run-$_"; userId = "s-u3-$run"; deviceId = "s-d3-$run"; ip = '10.0.0.1'; type = 'OFFER_COMPLETED'; playSeconds = 2; occurredAt = (& $now) } | ConvertTo-Json)
}
"BLOCK  : $($block | ConvertTo-Json -Compress)" | Add-Content $out
Get-Content $out

$smoke = Join-Path $proof 'smoke-test-aws.txt'
"BASE_URL=$BaseUrl" | Set-Content $smoke
$gitBash = 'C:\Program Files\Git\bin\bash.exe'  # PowerShell's plain `bash` may be a WSL stub
& $gitBash "$repo/scripts/smoke-test.sh" $BaseUrl 2>&1 | Tee-Object -FilePath $smoke -Append
$smokeExit = $LASTEXITCODE

k6 run -e BASE_URL=$BaseUrl -e API_KEY=$key "$repo/scripts/load.js" 2>&1 | Tee-Object -FilePath (Join-Path $proof 'k6-aws.txt')

Write-Host "smoke exit code: $smokeExit"
exit $smokeExit
