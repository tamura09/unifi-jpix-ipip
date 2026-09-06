#!/bin/bash
# systemd ユニットを /etc へ実ファイルで設置して有効化する。
# /etc は UniFi OS のアップグレードで消える可能性があるので、消えたら再実行する。
set -euo pipefail
cp -f /data/ipip/ipip-watch.service /etc/systemd/system/ipip-watch.service
systemctl daemon-reload
systemctl enable --now ipip-watch.service
systemctl --no-pager status ipip-watch.service | head -5
