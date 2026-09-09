param(
  [string]$Output = ".env",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function New-HexSecret([int]$Bytes = 32) {
  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($buffer)
  }
  finally {
    $rng.Dispose()
  }
  return ([System.BitConverter]::ToString($buffer)).Replace("-", "").ToLowerInvariant()
}

$root = Split-Path -Parent $PSScriptRoot
$template = Join-Path $root ".env.example"
$outFile = Join-Path $root $Output

if (-not (Test-Path $template)) {
  throw ".env.example nao encontrado em $template"
}

if ((Test-Path $outFile) -and -not $Force) {
  throw "$outFile ja existe. Use -Force para recriar."
}

$content = Get-Content $template -Raw

$replacements = @{
  "POSTGRES_ADMIN_PASSWORD=GENERATE_ME" = "POSTGRES_ADMIN_PASSWORD=$(New-HexSecret 24)"
  "POSTGRES_PASSWORD=GENERATE_ME"       = "POSTGRES_PASSWORD=$(New-HexSecret 24)"
  "REDIS_PASSWORD=GENERATE_ME"          = "REDIS_PASSWORD=$(New-HexSecret 24)"
  "N8N_ENCRYPTION_KEY=GENERATE_ME"      = "N8N_ENCRYPTION_KEY=$(New-HexSecret 32)"
  "TELEGRAM_WEBHOOK_SECRET=GENERATE_ME" = "TELEGRAM_WEBHOOK_SECRET=$(New-HexSecret 32)"
}

foreach ($key in $replacements.Keys) {
  $content = $content.Replace($key, $replacements[$key])
}

Set-Content -Path $outFile -Value $content -Encoding UTF8

Write-Host "Arquivo criado: $outFile" -ForegroundColor Green
Write-Host "Segredos locais gerados automaticamente." -ForegroundColor Green
Write-Host "Ainda precisam ser preenchidos externamente:" -ForegroundColor Yellow
Write-Host "  NASA_API_KEY"
Write-Host "  TELEGRAM_BOT_TOKEN"
Write-Host "  INSTAGRAM_ACCESS_TOKEN"
Write-Host "  INSTAGRAM_ACCOUNT_ID"
Write-Host "Depois do TELEGRAM_BOT_TOKEN, execute scripts/discover-telegram-ids.ps1 para descobrir os IDs." -ForegroundColor Cyan
