#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "$ENV_FILE nao encontrado. Execute primeiro scripts/generate-env.sh" >&2
  exit 1
fi

get_env() {
  key="$1"
  sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1
}

TOKEN="$(get_env TELEGRAM_BOT_TOKEN)"
if [ -z "$TOKEN" ]; then
  echo "TELEGRAM_BOT_TOKEN esta vazio no .env. Crie o bot no BotFather e preencha o token." >&2
  exit 1
fi

printf 'Envie uma mensagem qualquer para o bot no Telegram e pressione Enter... '
read _dummy

JSON="$(curl -fsS "https://api.telegram.org/bot${TOKEN}/getUpdates")"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 e necessario para interpretar a resposta do Telegram." >&2
  exit 1
fi

IDS="$(printf '%s' "$JSON" | python3 -c '
import sys, json
x=json.load(sys.stdin)
r=x.get("result") or []
if not x.get("ok") or not r:
    raise SystemExit(2)
u=r[-1]
m=u.get("message") or (u.get("callback_query") or {}).get("message") or {}
f=(u.get("message") or {}).get("from") or (u.get("callback_query") or {}).get("from") or {}
chat=(m.get("chat") or {}).get("id")
user=f.get("id")
if chat is None or user is None:
    raise SystemExit(3)
print(f"{chat}\n{user}")
')" || {
  echo "Nao foi possivel identificar IDs. Envie uma mensagem para o bot e tente novamente." >&2
  exit 1
}

CHAT_ID="$(printf '%s\n' "$IDS" | sed -n '1p')"
USER_ID="$(printf '%s\n' "$IDS" | sed -n '2p')"

TMP_FILE="${ENV_FILE}.tmp"
sed \
  -e "s/^TELEGRAM_CHAT_ID=.*/TELEGRAM_CHAT_ID=$CHAT_ID/" \
  -e "s/^TELEGRAM_ALLOWED_USER_ID=.*/TELEGRAM_ALLOWED_USER_ID=$USER_ID/" \
  "$ENV_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$ENV_FILE"
chmod 600 "$ENV_FILE" 2>/dev/null || true

echo "TELEGRAM_CHAT_ID=$CHAT_ID"
echo "TELEGRAM_ALLOWED_USER_ID=$USER_ID"
echo ".env atualizado automaticamente."
