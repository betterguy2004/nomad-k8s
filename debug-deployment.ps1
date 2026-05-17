$nomad = "http://13.56.102.151:4646"

# 1. Current jobs
Write-Host "=== CURRENT JOBS ===" -ForegroundColor Cyan
$jobs = Invoke-RestMethod -Uri "$nomad/v1/jobs" -UseBasicParsing -TimeoutSec 10
$jobs | ForEach-Object { Write-Host "$($_.ID): $($_.Status) ($($_.Type))" }

# 2. Check RDS in Consul KV
Write-Host "`n=== CONSUL KV: rds/endpoint ===" -ForegroundColor Cyan
try {
  $resp = Invoke-RestMethod -Uri "http://13.56.102.151:8500/v1/kv/rds/endpoint" -UseBasicParsing -TimeoutSec 5
  if ($resp) {
    $rds = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($resp[0].Value))
    Write-Host "FOUND: $rds" -ForegroundColor Green
  }
} catch {
  Write-Host "NOT FOUND - need to set via: consul kv put rds/endpoint <endpoint>" -ForegroundColor Yellow
}

# 3. Try WordPress submit
Write-Host "`n=== SUBMIT WORDPRESS ===" -ForegroundColor Cyan
try {
  $hcl = Get-Content -Raw 'D:\nomad-k8s\jobs\wordpress.nomad.hcl'
  $pb = @{JobHCL=$hcl;Canonicalize=$true} | ConvertTo-Json -Depth 20
  $p = Invoke-RestMethod -Method Post -Uri "$nomad/v1/jobs/parse" -Body $pb -ContentType 'application/json' -TimeoutSec 15
  $rb = @{Job=$p} | ConvertTo-Json -Depth 100
  $r = Invoke-RestMethod -Method Post -Uri "$nomad/v1/jobs" -Body $rb -ContentType 'application/json' -TimeoutSec 15
  Write-Host "SUCCESS: $($r.JobModifyIndex)" -ForegroundColor Green
} catch {
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# 4. Try Laravel submit
Write-Host "`n=== SUBMIT LARAVEL ===" -ForegroundColor Cyan
try {
  $hcl = Get-Content -Raw 'D:\nomad-k8s\jobs\laravel.nomad.hcl'
  $pb = @{JobHCL=$hcl;Canonicalize=$true} | ConvertTo-Json -Depth 20
  $p = Invoke-RestMethod -Method Post -Uri "$nomad/v1/jobs/parse" -Body $pb -ContentType 'application/json' -TimeoutSec 15
  $rb = @{Job=$p} | ConvertTo-Json -Depth 100
  $r = Invoke-RestMethod -Method Post -Uri "$nomad/v1/jobs" -Body $rb -ContentType 'application/json' -TimeoutSec 15
  Write-Host "SUCCESS: $($r.JobModifyIndex)" -ForegroundColor Green
} catch {
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Final check
Write-Host "`n=== FINAL JOB LIST ===" -ForegroundColor Cyan
$jobs = Invoke-RestMethod -Uri "$nomad/v1/jobs" -UseBasicParsing -TimeoutSec 10
$jobs | ForEach-Object { Write-Host "$($_.ID): $($_.Status)" }
