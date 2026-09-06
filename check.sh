#!/bin/bash
# 現状確認（読み取りのみ）
. /data/ipip/config.env
S=/data/udapi-config/ubios-udapi-server/ubios-udapi-server.state
IPV4_ADDR="${IPV4_CIDR%/*}"
echo "== 1. hb46pp 設定 =="
jq -c --arg IF "$WAN_IF" '.interfaces[]|select(.identification.id==$IF)|{cap:.ipv6.hb46pp.capability, auth:(if .ipv6.hb46pp.authentication then "あり" else "なし" end)}' "$S"
echo "== 2. WAN のグローバルIPv6 (無いと hb46pp は無言でハング) =="
ip -json a show "$WAN_IF" | jq -r '.[].addr_info[]|select(.family=="inet6" and .scope=="global")|"\(.local)/\(.prefixlen)"' || echo "  なし"
echo "== 3. hb46pp プロセス =="
pgrep -af "bash -s .* ${WAN_IF}$" || echo "  起動していない"
echo "== 4. トンネル =="
T=$(jq -r --arg IF "$WAN_IF" '.interfaces[]|select(.identification.type=="tunnel" and .tunnel.localAddress.id==$IF)|.identification.id' "$S")
[ -n "$T" ] && { ip -d link show "$T" 2>/dev/null | sed -n '2p'; ip -4 addr show "$T" | grep inet; } || echo "  トンネル無し"
echo "== 5. 送信元アドレス (固定IPになっていれば正常) =="
[ -n "$T" ] && ip route get 8.8.8.8 oif "$T" 2>/dev/null
echo "== 6. 直近ログ =="
journalctl --since '-10 min' --no-pager 2>/dev/null | grep -iE 'hb46pp|Provisioned (mode|local|remote|tunnel)' | sed 's/pass=[^&"]*/pass=<MASKED>/g' | tail -12
