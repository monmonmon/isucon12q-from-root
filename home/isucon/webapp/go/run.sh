#!/usr/bin/env bash

# タイムスタンプを付けてecho
say() {
    echo "$(date +%R:%S) ${*}"
}

# コマンドライン引数として今回の変更に関するコメントを渡すこと
if [ $# -eq 0 ]; then
    echo "Usage: $(basename $0) コメント"
    exit 1
fi

# コマンドが異常終了したら即終了
set -e

# このスクリプトのあるディレクトリに移動
cd $(dirname $0)

# goの文法チェック
go vet
# ミドルウェアの設定ファイルチェック
sudo nginx -t
sudo mysqld --validate-config

# ビルド
make
# ログファイル削除 (alp, pt-query-digest に食わせるログをまっさらにする)
sudo rm -f /var/log/mysql/mysql-slow.log /var/log/nginx/access.log
# アプリサーバ・ミドルウェア再起動
sudo systemctl restart isuports nginx mysql

# /initialize を叩いて軽く動作確認
sleep 1.5
curl -XPOST http://127.0.0.1:3000/initialize

# 解析結果の出力先のファイル名
output=$PWD/bench-$(date +'%Y%m%d%H%M%S').txt

# 今回の変更に関するコメントをファイルに出力
echo "$*" >> $output
echo >> $output

# ベンチ実行
echo ">> benchmark" >> $output
(
    cd /home/isucon/bench
    2>&1 ./bench -target-addr 127.0.0.1:443 | tee -a $output
    echo >> $output
)

# alpでアクセスログを解析
echo ">> alp" >> $output
alp ltsv --file /var/log/nginx/access.log --sort sum -r \
    -o method,uri,sum,count,min,max,avg \
    -m '/api/player/competition/[0-9a-f]+/ranking,/api/organizer/competition/[0-9a-f]+/score,/api/player/player/[0-9a-f]+,/api/organizer/player/[0-9a-f]+/disqualified,/api/organizer/competition/[0-9a-f]+/finish' \
    | tee -a $output
echo >> $output

# pt-query-digestでスロークエリログを解析
echo ">> pt-query-digest" >> $output
sudo pt-query-digest /var/log/mysql/mysql-slow.log | tee -a $output

# 解析結果ファイルをlessで開く
echo $output
exec less $output
