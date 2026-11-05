# Install check: runs AgenticProd.Verify.Run() inside the container. No LLM call, nothing of yours is changed.
# Usage: .\verify.ps1 [-Strict]   (-Strict counts a skipped replay step as a failure)
param([switch]$Strict)
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Host 'ERROR: docker is not installed or not on PATH' -ForegroundColor Red; exit 1 }
$cid = docker compose ps -q iris
if (-not $cid) { Write-Host 'ERROR: the iris container is not running; start it with .\install.ps1' -ForegroundColor Red; exit 1 }

$flag = if ($Strict) { 1 } else { 0 }
# The command is piped inside the container: Windows PowerShell 5.1 adds a BOM when it pipes text itself
$run = "printf 'Do ##class(AgenticProd.Verify).Run($flag)
Halt
' | iris session iris -U IRISAPP"
$out = docker compose exec -T iris sh -c $run
$lines = $out | Where-Object { $_ -match '^(AgenticProd verify|PASS|FAIL|SKIP|Verify )' }
$lines | ForEach-Object { Write-Host $_ }
if ($lines -match '^Verify PASSED') { exit 0 } else { exit 1 }
