#!/bin/bash
# watcher を停止・無効化して撤去する（config.env とスクリプトは残す）
set -uo pipefail
systemctl disable --now ipip-watch.service 2>/dev/null
rm -f /etc/systemd/system/ipip-watch.service
systemctl daemon-reload
echo "ipip-watch を撤去しました。設定を純正へ戻すには /data/ipip/revert.sh を実行してください。"
