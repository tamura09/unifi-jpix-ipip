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
umask 077
W=$(mktemp /run/ipip-work.XXXXXX); trap 'rm -f "$W"' EXIT
# 契約の user/pass は argv に載せない（ps や /proc/<pid>/cmdline から読めるため）。
# 環境変数で渡し、jq 側で env から読む。/proc/<pid>/environ は所有者と root しか読めない。
JPIX_USER="$USERNAME" JPIX_PASS="$PASSWORD" \
jq --indent 1 --arg IF "$WAN_IF" --arg sname "$SNAME" '
  .interfaces |= [ .[] |
    if .identification.id == $IF and .ipv6.hb46pp.capability == "map_e_jpix" then
        .ipv6.hb46pp.capability = "ipip_jpix"
      | .ipv6.hb46pp.authentication = { username:env.JPIX_USER, password:env.JPIX_PASS, serverName:$sname }
    else . end
    | if .identification.type == "tunnel" and (.tunnel.localAddress.id? == $IF) then
        .addresses |= [ .[] | select(.cidr == null or (.cidr | startswith("192.0.0.") | not)) ]
      else . end
  ]' "$S" > "$W"
if ! grep -q '"ipip_jpix"' "$W"; then
  echo "ERROR: ${WAN_IF} に map_e_jpix がありません。UIでMAP-E(v6プラス)を設定してください。" >&2; exit 1
fi
if [ "$DRY" = 1 ]; then
  # パスワードは jq で伏せてから diff を取る（sed の引数にも載せない）
  mask() {
    jq --indent 1 '.interfaces |= [ .[] |
      if .ipv6.hb46pp.authentication.password? then .ipv6.hb46pp.authentication.password = "<PASSWORD>" else . end ]' "$1"
  }
  diff -u --label "$S" --label "$S (適用後)" <(mask "$S") <(mask "$W") || true; exit 0
fi
if [ "$NOBAK" = 0 ]; then
  B=/data/udapi-config/ubios-udapi-server.state.bak.$(date +%Y%m%d-%H%M%S)
  cp -a "$S" "$B"; chmod 600 "$B"; echo "backup : $B"
  ls -1t /data/udapi-config/ubios-udapi-server.state.bak.* 2>/dev/null | tail -n +11 | xargs -r rm -f
fi
ubios-udapi-client put /system/ubios/udm/configuration "@${W}" >/dev/null
echo "applied: ${WAN_IF} -> ipip_jpix (${IPV4_ADDR}/${IPV4_PLEN})"
