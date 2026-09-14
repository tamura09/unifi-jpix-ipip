#!/bin/bash
# ipip_jpix を適用する。
#   --dry-run    差分のみ表示（適用しない）
#   --no-backup  バックアップを取らない（watcher 用）
set -euo pipefail
. /data/ipip/config.env
S=/data/udapi-config/ubios-udapi-server/ubios-udapi-server.state
DRY=0; NOBAK=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --no-backup) NOBAK=1;; esac; done
IPV4_ADDR="${IPV4_CIDR%/*}"; IPV4_PLEN="${IPV4_CIDR#*/}"
SNAME="${IPV6_IID}|${IPV6_REMOTE}|${IPV4_ADDR}|${IPV4_PLEN}"
# --dry-run では平文を一切出さない。出力を後段でマスクする方式は JSON の
# エスケープ（\ や " など）で取りこぼすため、jq に渡す時点で差し替える。
if [ "$DRY" = 1 ]; then PASS_VALUE="<PASSWORD>"; else PASS_VALUE="$PASSWORD"; fi
umask 077
W=$(mktemp /run/ipip-work.XXXXXX); trap 'rm -f "$W"' EXIT
# PASSWORD は --arg ではなく環境変数で渡す。プロセスの引数は /proc/<pid>/cmdline
# 経由で同一ホストの他ユーザーから読めるため（environ は所有者と root のみ）。
PASS="$PASS_VALUE" jq --indent 1 --arg IF "$WAN_IF" --arg user "$USERNAME" --arg sname "$SNAME" '
  .interfaces |= [ .[] |
    if .identification.id == $IF and .ipv6.hb46pp.capability == "map_e_jpix" then
        .ipv6.hb46pp.capability = "ipip_jpix"
      | .ipv6.hb46pp.authentication = { username:$user, password:env.PASS, serverName:$sname }
    else . end
    | if .identification.type == "tunnel" and (.tunnel.localAddress.id? == $IF) then
        .addresses |= [ .[] | select(.cidr == null or (.cidr | startswith("192.0.0.") | not)) ]
      else . end
  ]' "$S" > "$W"
if ! grep -q '"ipip_jpix"' "$W"; then
  echo "ERROR: ${WAN_IF} に map_e_jpix がありません。UIでMAP-E(v6プラス)を設定してください。" >&2; exit 1
fi
if [ "$DRY" = 1 ]; then diff -u "$S" "$W" || true; exit 0; fi
if [ "$NOBAK" = 0 ]; then
  B=/data/udapi-config/ubios-udapi-server.state.bak.$(date +%Y%m%d-%H%M%S)
  cp -a "$S" "$B"; chmod 600 "$B"; echo "backup : $B"
  ls -1t /data/udapi-config/ubios-udapi-server.state.bak.* 2>/dev/null | tail -n +11 | xargs -r rm -f
fi
ubios-udapi-client put /system/ubios/udm/configuration "@${W}" >/dev/null
echo "applied: ${WAN_IF} -> ipip_jpix (${IPV4_ADDR}/${IPV4_PLEN})"
