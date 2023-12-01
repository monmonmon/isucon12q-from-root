#!/usr/bin/env bash

# タイムスタンプ付きでecho
say() {
    echo
    echo "[$(date +%R:%S)] ${*}"
}

# コマンドが異常終了したら即終了
set -e

# このスクリプトのあるディレクトリに移動
cd $(dirname $0)

# goの文法チェック
go vet
# ミドルウェアの設定ファイルの文法チェック
sudo nginx -t
sudo mysqld --validate-config

# ビルド
make
# ログファイル削除 (alp, pt-query-digest に食わせるログをまっさらにする)
sudo rm -f /var/log/mysql/mysql-slow.log /var/log/nginx/access.log
# アプリサーバ・ミドルウェア再起動
sudo systemctl restart isuports nginx mysql

# /initialize を叩いて軽く動作確認
sleep 2
curl -XPOST http://127.0.0.1:3000/initialize

# 解析結果の出力先ディレクトリを準備
mkdir -p /results
rm -f /results/*

# ベンチをバックグラウンドで実行
say 'benchmark'
(
    cd /home/isucon/bench
    2>&1 ./bench -target-addr 127.0.0.1:443 | tee /results/bench.txt
) &
bench_pid=$!

# topで計測開始
top -b -d1 > >( grep --line-buffered -w PID -A8 ) > /results/top.txt &
top_pid=$!
# dstatで計測開始
dstat -tlamp > /results/dstat.txt &
dstat_pid=$!

# ベンチの終了を待機
wait $bench_pid
# top, dstatをkill
kill $top_pid $dstat_pid

# alpでアクセスログを解析
say 'alp'
alp ltsv --file /var/log/nginx/access.log --sort sum -r \
    -o method,uri,sum,count,min,max,avg \
    -m '/api/player/competition/[0-9a-f]+/ranking,/api/organizer/competition/[0-9a-f]+/score,/api/player/player/[0-9a-f]+,/api/organizer/player/[0-9a-f]+/disqualified,/api/organizer/competition/[0-9a-f]+/finish' \
    | tee /results/alp.txt

# pt-query-digestでスロークエリログを解析
say 'pt-query-digest'
sudo pt-query-digest --explain 'h=localhost,u=isucon,p=isucon,D=isuports' /var/log/mysql/mysql-slow.log \
    | tee /results/slow-query.txt

say 'done'
