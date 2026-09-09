param(
  [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root $EnvFile

if (-not (Test-Path $path)) {
  throw "$path nao encontrado. Execute primeiro scripts/generate-env.ps1"
}

$lines = Get-Content $path
$vars = @{}
foreach ($line in $lines) {
  if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
  $parts = $line -split '=', 2
  $vars[$parts[0].Trim()] = $parts[1].Trim()
}

$token = $vars['TELEGRAM_BOT_TOKEN']
if ([string]::IsNullOrWhiteSpace($token)) {
  throw 'TELEGRAM_BOT_TOKEN esta vazio no .env. Crie o bot no BotFather e preencha o token.'
}

Write-Host 'Envie uma mensagem qualquer para o bot no Telegram e pressione Enter.' -ForegroundColor Cyan
[void](Read-Host)

$url = "https://api.telegram.org/bot$token/getUpdates"
$response = Invoke-RestMethod -Method Get -Uri $url

if (-not $response.ok -or -not $response.result -or $response.result.Count -eq 0) {
  throw 'Nenhuma atualizacao encontrada. Envie uma mensagem para o bot e tente novamente.'
}

$update = $response.result[-1]
$message = $update.message
if (-not $message) {
  $message = $update.callback_query.message
}

$userId = $null
if ($update.message.from.id) {
  $userId = [string]$update.message.from.id
} elseif ($update.callback_query.from.id) {
  $userId = [string]$update.callback_query.from.id
}

$chatId = [string]$message.chat.id

if (-not $chatId -or -not $userId) {
  throw 'Nao foi possivel identificar chat_id/user_id na ultima atualizacao.'
}

$content = Get-Content $path -Raw
$content = [regex]::Replace($content, '(?m)^TELEGRAM_CHAT_ID=.*$', "TELEGRAM_CHAT_ID=$chatId")
$content = [regex]::Replace($content, '(?m)^TELEGRAM_ALLOWED_USER_ID=.*$', "TELEGRAM_ALLOWED_USER_ID=$userId")
Set-Content -Path $path -Value $content -Encoding UTF8

Write-Host "TELEGRAM_CHAT_ID=$chatId" -ForegroundColor Green
Write-Host "TELEGRAM_ALLOWED_USER_ID=$userId" -ForegroundColor Green
Write-Host '.env atualizado automaticamente.' -ForegroundColor Green
