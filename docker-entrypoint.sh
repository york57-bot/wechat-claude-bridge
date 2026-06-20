#!/bin/bash
set -e

ACCOUNTS_DIR="/root/.wechat-claude-code/accounts"

# If account data provided via env, write it
if [ -n "$WCC_ACCOUNT_JSON" ] && [ ! -f "$ACCOUNTS_DIR"/*.json ]; then
  echo "$WCC_ACCOUNT_JSON" > "$ACCOUNTS_DIR/account.json"
  echo "Account loaded from WCC_ACCOUNT_JSON"
fi

# If config provided via env, write it
if [ -n "$WCC_CONFIG_JSON" ] && [ ! -f /root/.wechat-claude-code/config.json ]; then
  echo "$WCC_CONFIG_JSON" > /root/.wechat-claude-code/config.json
  echo "Config loaded from WCC_CONFIG_JSON"
fi

# Verify we have account data
if [ -z "$(ls -A "$ACCOUNTS_DIR" 2>/dev/null)" ]; then
  echo "=============================================="
  echo "  No account data found."
  echo "  Run setup locally first, then provide:"
  echo "    WCC_ACCOUNT_JSON  (cat ~/.wechat-claude-code/accounts/*.json)"
  echo "    WCC_CONFIG_JSON   (cat ~/.wechat-claude-code/config.json)"
  echo "=============================================="
  exit 1
fi

echo "Starting wechat-claude-code daemon..."
exec node /app/dist/main.js start
