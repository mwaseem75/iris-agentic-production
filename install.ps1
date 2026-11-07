# One-command install: checks Docker and the image, creates .env, builds and starts, waits for healthy.
# Usage: .\install.ps1 [-ImageTar path\to\the-tar-file-from-the-portal]   (or set IRIS_IMAGE_TAR; not needed when the image is already loaded)
param([string]$ImageTar = $env:IRIS_IMAGE_TAR)
# Continue: with Stop, Windows PowerShell 5.1 throws when a native command writes to stderr
$ErrorActionPreference = 'Continue'
$Url = 'http://localhost:52773/agenticprod/AgenticProd.UI.Home.cls'

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# Native commands do not throw in PowerShell, so every call checks $LASTEXITCODE
function Test-Image {
    $null = docker image inspect $Image 2>&1
    return ($LASTEXITCODE -eq 0)
}

Set-Location $PSScriptRoot

# Image name: environment first, then .env, then the tested build
$Image = $env:IRIS_IMAGE
if (-not $Image -and (Test-Path .env)) {
    $line = Select-String -Path .env -Pattern '^IRIS_IMAGE=(.+)$' | Select-Object -Last 1
    if ($line) { $Image = $line.Matches[0].Groups[1].Value.Trim().Trim('"') }
}
if (-not $Image) { $Image = 'irishealth-community:2027.1.0AI.109.0' }
$env:IRIS_IMAGE = $Image

# 1. Docker and compose
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Fail 'docker is not installed or not on PATH' }
$null = docker info 2>&1
if ($LASTEXITCODE -ne 0) { Fail 'docker is installed but the daemon is not running' }
$null = docker compose version 2>&1
if ($LASTEXITCODE -ne 0) { Fail "'docker compose' (v2) is not available" }

# 2. The AI Hub image is not public. It comes as a tar file from the AI Hub early-access portal;
# docker load prints its internal name, and the app builds FROM the short tag. Take the tar path,
# an image that is already loaded under the internal name, or one already tagged.
$Internal = 'docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0'
if (-not (Test-Image)) {
    if ($ImageTar) {
        if (-not (Test-Path $ImageTar)) { Fail "image file not found: $ImageTar" }
        Write-Host "Loading $ImageTar (this takes a minute)..."
        $out = docker load -i $ImageTar
        if ($LASTEXITCODE -ne 0) { Fail 'docker load failed' }
        $out | ForEach-Object { Write-Host $_ }
        $loaded = ($out | Where-Object { $_ -like 'Loaded image:*' } | Select-Object -Last 1) -replace '^Loaded image:\s*', ''
        if (-not $loaded) { Fail "docker load did not print a 'Loaded image:' name" }
        Write-Host "Running: docker tag $loaded $Image"
        docker tag $loaded $Image
        if ($LASTEXITCODE -ne 0) { Fail "docker tag failed for $loaded" }
    } else {
        $null = docker image inspect $Internal 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Found the loaded image $Internal"
            Write-Host "Running: docker tag $Internal $Image"
            docker tag $Internal $Image
            if ($LASTEXITCODE -ne 0) { Fail "docker tag failed for $Internal" }
        }
    }
}
if (-not (Test-Image)) {
    Write-Host @"
ERROR: the image $Image is missing.

This app needs $Image (InterSystems IRIS for Health with AI Hub, early access
build 109, built on build 154). The plain iris-community image of the same build does not work: it has no
EnsLib.HL7 classes, and setup stops with a message saying so. The image is not public: download the
tar file from the AI Hub early-access portal, then load it and tag it:

  docker load -i <the tar file from the portal>
  docker tag docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0 $Image

docker load prints that internal name. Or run: .\install.ps1 -ImageTar path\to\the-tar-file-from-the-portal
Never push this image, or an image built from it, to a public registry.
"@ -ForegroundColor Red
    exit 1
}

# 3. .env: created once, never overwritten, never printed
if (-not (Test-Path .env)) {
    if (-not (Test-Path .env.example)) { Fail '.env.example is missing' }
    Copy-Item .env.example .env
    Write-Host 'Created .env from .env.example'
}
if (-not (Select-String -Path .env -Pattern '^OPENAI_API_KEY=.+' -Quiet)) {
    Write-Host 'OPENAI_API_KEY is empty in .env: replay mode works without a key. Add one for live mode.'
}

# 4. Build and start
Write-Host 'Building and starting (first build will take some time)...'
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { Fail 'docker compose up failed' }

# 5. Wait for the healthcheck: up to 20 minutes, one dot every 15 seconds
$cid = (docker compose ps -q iris | Select-Object -First 1)
if (-not $cid) { Fail 'the iris container was not created' }
Write-Host -NoNewline 'Waiting for IRIS to be healthy (setup runs on first start)'
$healthy = $false
for ($i = 0; $i -lt 80; $i++) {
    $state = docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $cid
    if ($state -eq 'healthy') { $healthy = $true; break }
    Write-Host -NoNewline '.'
    Start-Sleep -Seconds 15
}
Write-Host ''
if (-not $healthy) {
    Write-Host 'ERROR: IRIS was not healthy after 20 minutes. Last 20 log lines:' -ForegroundColor Red
    docker compose logs --tail 20 iris
    exit 1
}

Write-Host @"

Ready.
  Dashboard:  $Url
  Logins:     SuperUser / SYS (demo admin)
              reviewer / Review-Demo-2026 (read-only)

Replay the recorded evaluation (no key, no cost), in the IRISAPP terminal:
  docker compose exec iris iris session iris -U IRISAPP
  do ##class(AgenticProd.Eval.Runner).Run("gpt-4o-mini", "replay demo", "all", "replay")
"@
