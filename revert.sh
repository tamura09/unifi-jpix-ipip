#!/bin/bash
# ipip_jpix を純正の map_e_jpix へ戻す。
set -euo pipefail
. /data/ipip/config.env
S=/data/udapi-config/ubios-udapi-server/ubios-udapi-server.state
umask 077
W=$(mktemp /run/ipip-rev.XXXXXX); trap 'rm -f "$W"' EXIT
jq --indent 1 --arg IF "$WAN_IF" '
  .interfaces |= [ .[] |
    if .identification.id == $IF and .ipv6.hb46pp.capability == "ipip_jpix" then
        .ipv6.hb46pp.capability = "map_e_jpix" | del(.ipv6.hb46pp.authentication)
    else . end ]' "$S" > "$W"
ubios-udapi-client put /system/ubios/udm/configuration "@${W}" >/dev/null
echo "reverted: ${WAN_IF} -> map_e_jpix"
