# ファイル名: future_mining_energy_40years.rb

require 'time'
require 'net/http'
require 'json'

# ------------------------------------------------------------
# (共通) 現在の BTC/JPY を Blockchain.com API から取得する関数
# ------------------------------------------------------------
# もともとの
#   btc = JSON.parse(Net::HTTP.get(URI.parse('https://blockchain.info/tickers')).gsub("\n", ''))
#   btc_jpy = btc["BTC"]["JPY"]["last"]
# は、API 側が 500 Internal Server Error などで HTML を返したときに
# その HTML を JSONとしてパースしようとして JSON::ParserError を起こしていた。
#
# ここでは、
#   - HTTP ステータスコードを確認し、200 OK のときだけ JSON.parse する
#   - それ以外（500など）のときはエラーメッセージを出して例外を投げる
# という形で安全にラップする。

def fetch_btc_jpy_from_blockchain
  uri = URI.parse('https://blockchain.info/tickers')

  # ステータスコード付きのレスポンスを取得
  response = Net::HTTP.get_response(uri)

  # 200 OK 以外はサーバ側のエラーなどとみなす
  unless response.is_a?(Net::HTTPSuccess)
    warn "[WARN] HTTP error from blockchain.info: #{response.code} #{response.message}"
    warn "[WARN] response body (head 200 chars): #{response.body[0, 200]}"
    raise "Blockchain API error (status #{response.code})"
  end

  body = response.body

  # JSON 以外（HTMLエラーページなど）が返ってきた場合に備えて例外処理を付ける
  begin
    tickers = JSON.parse(body)
  rescue JSON::ParserError => e
    warn "[WARN] JSON parse error: #{e.message}"
    warn "[WARN] response body (head 200 chars): #{body[0, 200]}"
    raise "Blockchain API returned invalid JSON"
  end

  # 期待しているパス: ["BTC"]["JPY"]["last"]
  btc_info = tickers["BTC"]
  jpy_info = btc_info && btc_info["JPY"]

  unless jpy_info && jpy_info["last"]
    raise "Unexpected JSON structure: BTC/JPY 'last' not found"
  end

  jpy_info["last"].to_f
end

# ------------------------------------------------------------
# 現在の BTC/JPY を取得（APIエラー時はフォールバック値を使用）
# ------------------------------------------------------------
begin
  btc_jpy = fetch_btc_jpy_from_blockchain
  puts "APIから取得した BTC/JPY (last): #{btc_jpy} 円"
rescue => e
  warn "[WARN] APIからの取得に失敗しました: #{e.message}"
  warn "[WARN] フォールバックとして、教科書用の固定値を使用します。"
  # 問題文に基づく 2021年7月2日時点の参考値
  btc_jpy = 3_676_342.41
  puts "フォールバック BTC/JPY (固定値): #{btc_jpy} 円"
end

# ------------------------------------------------------------
# 前提：
# - 「ビットコインの市場価格が現在のまま固定される」と仮定する。
#   → 上で取得した btc_jpy を今後40年ずっと使い続けるとみなす。
# - 1ブロックあたりの報酬は、ビットコインの仕様通り
#     初期報酬 50 BTC からスタートし、
#     210,000 ブロックごとに 1/2 ずつ半減していく。
# - ここでは、40年後の「その時点のブロック報酬」を求め、
#   「その報酬が電力コストとちょうど等しい」と仮定して、
#   必要な消費電力量を計算する。
# ------------------------------------------------------------

# 40年後を秒数で表現する。
# 365.25 日/年 でうるう年を近似し、40 年分を秒に変換。
years_after = 40
seconds_per_year = 365.25 * 24 * 60 * 60
delta_seconds_40y = seconds_per_year * years_after

# 「現在時刻」
now_time = Time.now

# 「40年後の時刻」＝ 現在 + 40年
future_time = now_time + delta_seconds_40y

# ------------------------------------------------------------
# ビットコインの報酬スケジュールに基づき、
# 40年後の 1ブロックあたり報酬 reward2 [BTC] を求める。
# ------------------------------------------------------------

# ジェネシスブロックのタイムスタンプ（JST）
genesis_time = Time.new(2009, 1, 4, 3, 15, 5, '+09:00')

# 1ブロックの平均生成時間（秒）
block_interval_sec = 600        # 10分 = 600秒

# 何ブロックごとに報酬が半減するか（ビットコイン仕様）
halving_interval_blocks = 210_000

# 1回の「半減期」に相当する時間（秒）
halving_period_sec = block_interval_sec * halving_interval_blocks
# = 600 * 210000 = 126000000 秒 ≒ 約4年

# ジェネシスから「40年後」までの経過秒数
elapsed_sec_to_future = future_time - genesis_time

# 経過時間が「半減期」の何回分に相当するか（実数）
raw_halving_count = elapsed_sec_to_future / halving_period_sec

# 実際に完了している半減回数は床関数で決まる
halving_count_future = raw_halving_count.floor

# 初期報酬（ジェネシス時点のブロック報酬）[BTC]
initial_reward_btc = 50.0

# 40年後の 1ブロックあたり報酬 [BTC]
#   reward2 = 50 * (1/2)^(半減回数)
reward2 = initial_reward_btc * (0.5 ** halving_count_future)

# ------------------------------------------------------------
# 「市場価格は現在のまま固定」と仮定したときの、
# 40年後の 1ブロックあたりの収入 [円] を計算する。
# ------------------------------------------------------------
# btc_jpy は現在の 1 BTC あたりの価格 [円/BTC]
revenue_future_block_jpy = btc_jpy * reward2

# ------------------------------------------------------------
# 電力単価 5 円/kWh, 10 円/kWh のとき、
# 「報酬と一致する消費電力量 (kWh)」を求める。
# ------------------------------------------------------------
# 理論式：
#   収入 R [円]、電力単価 p [円/kWh]、消費電力量 E [kWh] とすると、
#
#       収入 = 電気代
#       R = p * E
#
#   が「収支トントン（利益ゼロ）」となる条件である。
#   よって、
#
#       E = R / p
#
#   となる。
#
# ここで、R = revenue_future_block_jpy とする。

# 電力単価 5 円/kWh の場合
price_5yen_per_kwh = 5.0  # [円/kWh]

# 40年後の1ブロック分の報酬とちょうど釣り合う消費電力量 [kWh]
energy_kwh_5yen_future = revenue_future_block_jpy / price_5yen_per_kwh

# 規模感を把握するため GWh (= 10^6 kWh) に変換
energy_gwh_5yen_future = energy_kwh_5yen_future / 1_000_000.0

# 電力単価 10 円/kWh の場合
price_10yen_per_kwh = 10.0  # [円/kWh]

energy_kwh_10yen_future = revenue_future_block_jpy / price_10yen_per_kwh
energy_gwh_10yen_future = energy_kwh_10yen_future / 1_000_000.0

# ------------------------------------------------------------
# 結果の表示
# ------------------------------------------------------------
puts "===== 40年後のマイニング条件（市場価格は現在と同じと仮定）====="
puts "現在時刻:                  #{now_time}"
puts "40年後の時刻:              #{future_time}"
puts "ジェネシス時刻:            #{genesis_time}"
puts "経過秒数(ジェネシス→40年後): #{elapsed_sec_to_future.to_i} 秒"
puts "半減期(秒):                #{halving_period_sec} 秒"
puts "40年後までの半減回数:      #{halving_count_future} 回"
puts "40年後の1ブロック報酬:     #{reward2} BTC"
puts "BTC/JPY（現在価格仮定）:   #{btc_jpy} 円/BTC"
puts "40年後1ブロックの収入:     #{revenue_future_block_jpy} 円"

puts
puts "電力単価 5 円/kWh のときに収入と一致する消費電力量:"
puts "  E_5yen_future  = #{energy_kwh_5yen_future} kWh （1ブロック≒10分あたり）"
puts "                 = #{energy_gwh_5yen_future} GWh"

puts
puts "電力単価 10 円/kWh のときに収入と一致する消費電力量:"
puts "  E_10yen_future = #{energy_kwh_10yen_future} kWh （1ブロック≒10分あたり）"
puts "                 = #{energy_gwh_10yen_future} GWh"

# ------------------------------------------------------------
# コメント：
# - 40年後には半減回数がかなり進むため、reward2 は現在よりさらに小さくなる。
#   （ビットコインの設計上、報酬は指数関数的に減少していく）
# - 同じ電力単価 p のもとでは、許容される電力量 E は
#     E = (reward2 × btc_jpy) / p
#   によって決まり、reward2 が小さくなるほど E も小さくなる。
# - 「市場価格が現在のまま」というのは現実には強い仮定だが、
#   報酬半減とコスト構造の関係を理論的に考える上では分かりやすい理想化である。