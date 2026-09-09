#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEMPLATE="$ROOT_DIR/.env.example"
OUTPUT="$ROOT_DIR/.env"

if [ ! -f "$TEMPLATE" ]; then
  echo ".env.example nao encontrado em $TEMPLATE" >&2
  exit 1
fi

if [ -f "$OUTPUT" ] && [ "${1:-}" != "--force" ]; then
  echo "$OUTPUT ja existe. Use --force para recriar." >&2
  exit 1
fi

hex_secret() {
  bytes="$1"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes"
  else
    dd if=/dev/urandom bs=1 count="$bytes" 2>/dev/null | od -An -tx1 | tr -d ' \n'
  fi
}

POSTGRES_ADMIN_PASSWORD="$(hex_secret 24)"
POSTGRES_PASSWORD="$(hex_secret 24)"
REDIS_PASSWORD="$(hex_secret 24)"
N8N_ENCRYPTION_KEY="$(hex_secret 32)"
TELEGRAM_WEBHOOK_SECRET="$(hex_secret 32)"

sed \
  -e "s|POSTGRES_ADMIN_PASSWORD=GENERATE_ME|POSTGRES_ADMIN_PASSWORD=$POSTGRES_ADMIN_PASSWORD|" \
  -e "s|POSTGRES_PASSWORD=GENERATE_ME|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" \
  -e "s|REDIS_PASSWORD=GENERATE_ME|REDIS_PASSWORD=$REDIS_PASSWORD|" \
  -e "s|N8N_ENCRYPTION_KEY=GENERATE_ME|N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY|" \
  -e "s|TELEGRAM_WEBHOOK_SECRET=GENERATE_ME|TELEGRAM_WEBHOOK_SECRET=$TELEGRAM_WEBHOOK_SECRET|" \
  "$TEMPLATE" > "$OUTPUT"

chmod 600 "$OUTPUT" 2>/dev/null || true

echo "Arquivo criado: $OUTPUT"
echo "Segredos locais gerados automaticamente."
echo "Ainda precisam ser preenchidos externamente:"
echo "  NASA_API_KEY"
echo "  TELEGRAM_BOT_TOKEN"
echo "  INSTAGRAM_ACCESS_TOKEN"
echo "  INSTAGRAM_ACCOUNT_ID"
echo "Depois do TELEGRAM_BOT_TOKEN, execute scripts/discover-telegram-ids.sh para descobrir os IDs."
