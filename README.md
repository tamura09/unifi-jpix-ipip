# v6プラス固定IP (JPIX) を UniFi UCG-Fiber で終端する手順

UniFi OS 5.1.31 / UCG-Fiber で確認。UI に無い内部 capability `ipip_jpix` を直接使う **非公式** の方法。
FW 更新で壊れる可能性があり、サポート対象外になり得る。

- 対象ポート: **Port 5 = eth4**（`config.env` の `WAN_IF`）
- 契約値: `config.env`（chmod 600）

---

## 0. 前提（UI で先にやること）

Network → Settings → Internet → **WAN1 (Port 5)**

1. **IPv6 Connection = 単一ネットワーク (SLAAC)**
   - DHCPv6 にしてはいけない。この HGW は IA_NA を返さないため、
     WAN にグローバル IPv6 が付かず `ubnt-hb46pp` が**無言でハングする**
     （`select_preferred_addresses` の `sleep 1` 無限ループ。ログも出ない）
   - Prefix Delegation を使う場合、サイズは上流の構成で変わる。**ONU に直結なら 56、
     HGW を経由するなら 60**。SLAAC でも PD 要求は止まらない
2. **IPv4 Connection = IPv4 over IPv6 → MAP-E → v6 Plus**
   - これで `eth4.ipv6.hb46pp = {capability:"map_e_jpix", enabled:true}` が生成される
   - 動的 MAP-E として一度通ることを確認してから次へ進む

確認:

    /data/ipip/check.sh

- 「2. WAN のグローバルIPv6」に `240b:...` が出ること
- ログに `hb46pp (map_e_jpix): provisioning completed` が出ること

---

## 1. 差分確認 → 適用

    /data/ipip/apply.sh --dry-run     # 差分のみ（パスワードはマスク）
    /data/ipip/apply.sh               # 適用（自動でバックアップを取る）

適用で変わるのは 2 箇所だけ:

- `eth4.ipv6.hb46pp.capability` : `map_e_jpix` → `ipip_jpix`、`authentication` を追加
- eth4 のトンネル（ip6tnl*）から `192.0.0.x/29` プレースホルダを削除

**適用時に外向き通信が発生する**: `http://fcs.enabler.ne.jp/update?user=...&pass=...` へ
更新通知が飛び、固定IP `203.0.113.10` の宛先が「今この機器の IPv6」に登録し直される。
**他の機器（HGW / IX / RTX 等）でこの固定IPを終端している場合、その登録を奪う。**

## 2. 確認

    /data/ipip/check.sh

期待値:

    cap        : ipip_jpix / auth: あり
    トンネル    : local <eth4の/64>:cb:71:a00:0  remote 2404:9200:225:100::65
    IPv4       : 203.0.113.10/32
    送信元      : src 203.0.113.10        ← 192.0.0.x なら異常（上りだけ壊れる）

さらに厳密に見るなら:

    tcpdump -ni <トンネルIF>          # 出て行くパケットの送信元が固定IPか

## 3. 維持（必須）

**単発の適用では維持できない。** 実測で適用の約 75 秒後に `map_e_jpix` へ巻き戻った。
引き金は `config-migrate-helper: Trying to migrate config due to inconsistency`
→ `service: vvv Apply new configuration`。UI を触っていなくても発生する。

    /data/ipip/install-watch.sh       # watcher を有効化
    journalctl -ft ipip-watch         # 動作ログ
    systemctl status ipip-watch

watcher は state を 3 秒間隔でポーリングし、`map_e_jpix` へ戻っていたら
5 秒デバウンスの後に `apply.sh --no-backup` を実行する。

> より作り込まれた実装（inotify + Go 常駐）が公開されている:
> https://github.com/lictl/unifi-jpix-fixed-ip

## 4. 切り戻し

    /data/ipip/uninstall-watch.sh     # 先に watcher を止める（止めないと再適用されて戻らない）
    /data/ipip/revert.sh              # ipip_jpix → map_e_jpix

丸ごと戻したい場合は適用前のバックアップを流し込む:

    ls -1t /data/udapi-config/ubios-udapi-server.state.bak.*
    ubios-udapi-client put /system/ubios/udm/configuration "@<上のファイル>"

最終手段として、UI で WAN1 の設定を保存し直せばコントローラが純正状態を再生成する。

---

## 契約値と注意点

以下の表とサンプル中の契約値は**すべて例示値**です (RFC5737 / RFC3849 のドキュメント用アドレス)。
`config.example.env` を `config.env` にコピーし、契約書の値へ置き換えてください。
BR アドレスだけは JPIX 共通の実値です。

| 項目 | 値 |
|---|---|
| v4 アドレス | 203.0.113.10/32 |
| インターフェイスID | 00cb:0071:0a00:0000 |
| BR アドレス | 2404:9200:225:100::65 |
| ユーザID | kotei0000000000 |

**IID は先頭に `::` が必須。** 契約書の `00cb:0071:0a00:0000` をそのまま入れると
計算層 `/usr/bin/ubnt_hb46pp_calc.py` が落ちる:

    ipaddress.AddressValueError: Exactly 8 parts expected without '::' in '00cb:0071:0a00:0000'

`config.env` では `IPV6_IID="::00cb:0071:0a00:0000"` としてある。

ファームの検証条件（`/usr/bin/ubnt-hb46pp`）:

- username / password : `^[A-Za-z0-9]{1,20}$`
- serverName : `IID|IPv6_Remote|IPv4_Address|IPv4_Prefix_Length`（4分割・空要素不可）

トンネルのローカル端点は **WAN の /64 + 契約 IID** で合成される。
PD で受け取るプレフィックス（`/56` または `/60`）はトンネルに一切関与しない（LAN 配布用）。

計算だけ手元で確かめる（副作用なし）:

    echo '{"encoded_params":"::00cb:0071:0a00:0000|2404:9200:225:100::65|203.0.113.10|32"}' \
      | /usr/bin/ubnt_hb46pp_calc.py ipip_jpix eth4 <eth4のグローバルIPv6>

## トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| ログが一切出ず何も起きない | WAN にグローバル IPv6 が無い | UI で IPv6 を SLAAC に |
| `apply.sh` が「map_e_jpix がありません」 | UI で MAP-E 未設定 | 手順 0 を実施 |
| 下りは届くが上りが通らない | `192.0.0.x` が残存 | `ip addr del 192.0.0.X/29 dev <トンネルIF>` |
| すぐ `map_e_jpix` に戻る | コントローラの再生成 | watcher を有効化（手順 3）|
| `address update notification failed` | 認証失敗 / IPv6 経路無し | `config.env` の user/pass を確認 |

## ファイル一覧

    config.example.env               契約値のひな形（config.env にコピーして使う）
    /data/ipip/apply.sh              適用（--dry-run / --no-backup）
    /data/ipip/revert.sh             純正へ戻す
    /data/ipip/check.sh              状態確認（読み取りのみ）
    /data/ipip/watch.sh              巻き戻し検知＋再適用
    /data/ipip/ipip-watch.service    systemd ユニット（原本）
    /data/ipip/install-watch.sh      ユニット設置＋有効化
    /data/ipip/uninstall-watch.sh    ユニット撤去

`/data` は再起動・FW 更新でも残る。`/etc/systemd/system` は FW 更新で消えることがあるので、
watcher が消えたら `install-watch.sh` を再実行する。
