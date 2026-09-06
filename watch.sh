#!/bin/bash
# map_e_jpix へ巻き戻ったら ipip_jpix を再適用する（ポーリング型 / 3秒間隔・5秒デバウンス）
set -uo pipefail
. /data/ipip/config.env
S=/data/udapi-config/ubios-udapi-server/ubios-udapi-server.state
is_reverted() {
  jq -e --arg IF "$WAN_IF" \
    '.interfaces[]|select(.identification.id==$IF and .ipv6.hb46pp.capability=="map_e_jpix")' \
    "$S" >/dev/null 2>&1
}
logger -t ipip-watch "started (if=${WAN_IF})"
while true; do
  if is_reverted; then
    sleep 5
    if is_reverted; then
      logger -t ipip-watch "map_e_jpix へ巻き戻り検出 → 再適用"
      if /data/ipip/apply.sh --no-backup >/dev/null 2>&1; then
        logger -t ipip-watch "再適用 成功"
      else
        logger -t ipip-watch "再適用 失敗"
        sleep 20
      fi
    fi
  fi
  sleep 3
done
