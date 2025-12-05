# ファイル名: mining_energy_equivalent.rb

require 'net/http'
require 'json'

reward=50*(0.5**(((Time.now-Time.new(2009,1,4,3,15,5,'+09:00'))/(600*210000)).floor))

# 2021年７月２日時点で 6.25 BTC

# ------------------------------------------------------------
# (2) の補強：BTC/JPY 現在価格を API から安全に取得する
# ------------------------------------------------------------
# もとのコード：
#   btc = JSON.parse(Net::HTTP.get(URI.parse('https://blockchain.info/tickers')).gsub("\n",''))
#   btc_jpy = btc["BTC"]["JPY"]["last"]
#
# は、API 側が 500 Internal Server Error などで HTML を返した場合でも
# そのまま JSON.parse に渡してしまうため、
#
#   JSON::ParserError: '<head><title>500 Internal Server Error...</title></head>'
#
# のような例外が発生していた。
#
# そこで：
#   - HTTP ステータスコードを確認し、200 のときだけ JSON としてパース
#   - パースに失敗したらエラーメッセージを出し、固定値にフォールバック
# という形に修正する。

def fetch_btc_jpy_from_blockchain
  uri = URI.parse('https://blockchain.info/tickers')

  # ステータスコードも含めたレスポンスを取得
  response = Net::HTTP.get_response(uri)

  # 200 OK 以外はサーバ側エラーなどとみなし、例外にする
  unless response.is_a?(Net::HTTPSuccess)
    warn "[WARN] HTTP error from blockchain.info: #{response.code} #{response.message}"
    warn "[WARN] response body (head 200 chars): #{response.body[0, 200]}"
    raise "Blockchain API error (status #{response.code})"
  end

  body = response.body

  # JSON 以外（500 の HTML エラーページなど）が返ってきた場合の防御
  begin
    tickers = JSON.parse(body)
  rescue JSON::ParserError => e
    warn "[WARN] JSON parse error: #{e.message}"
    warn "[WARN] response body (head 200 chars): #{body[0, 200]}"
    raise "Blockchain API returned invalid JSON"
  end

  # 期待するパス: ["BTC"]["JPY"]["last"]
  btc_info = tickers["BTC"]
  jpy_info = btc_info && btc_info["JPY"]

  unless jpy_info && jpy_info["last"]
    raise "Unexpected JSON structure: BTC/JPY 'last' not found"
  end

  jpy_info["last"].to_f
end

# ------------------------------------------------------------
# BTC/JPY の取得（失敗時はフォールバック）
# ------------------------------------------------------------
begin
  btc_jpy = fetch_btc_jpy_from_blockchain
  puts "APIから取得した BTC/JPY (last): #{btc_jpy} 円"
rescue => e
  warn "[WARN] APIからの取得に失敗しました: #{e.message}"
  warn "[WARN] フォールバックとして、教科書用の固定値を使用します。"
  # 2021年7月2日時点での参考値（問題文より）
  btc_jpy = 3_676_342.41
  puts "フォールバック BTC/JPY (固定値): #{btc_jpy} 円"
end

# ------------------------------------------------------------
# 前提：
# - reward  : 1ブロックあたりのマイニング報酬（BTC）
#   （例：2021年7月2日時点なら 6.25 BTC）
# - btc_jpy : 1 BTC あたりの市場価格（円）
#   （例：2021年7月2日時点なら約 3,676,342.41 円）
#
# ここでは reward は (1) のコード（current_block_reward.rb）で
# すでに求めてあるものが同じ IRB セッションなどに残っている前提。
# 単体で実行したい場合は、例えば：
#
#   reward = 6.25  # 2021-07-02 時点の報酬（BTC）
#
# のように明示的に代入しておく。
# ------------------------------------------------------------

# ------------------------------------------------------------
# (3) 電力単価 5 円/kWh, 10 円/kWh のとき
#     マイニング報酬とちょうど一致する「消費電力量 (kWh)」を求める
# ------------------------------------------------------------
# ■理論的な関係式
#   1ブロック（≒10分）あたりの収入を R [円]、
#   電力単価を p [円/kWh]、
#   同じ10分間に消費した電力量を E [kWh]
#   とすると、
#
#       収入 ＝ 電気代
#       R = p * E
#
#   が「収支トントン（利益ゼロ）」となる条件である。
#   よって、E は
#
#       E = R / p   [kWh]
#
#   で与えられる。
#
#   ここで R は
#
#       R = reward（BTC） × btc_jpy（円/BTC）
#
#   なので、
#
#       E = (reward × btc_jpy) / p
#
#   と書ける。
#
#   p を 5 円/kWh と 10 円/kWh に変えて E を計算すれば、
#   「10分あたりの報酬とちょうど一致する電力量 (kWh)」が得られる。

# ------------------------------------------------------------
# 1. 1ブロック（10分）あたりの収入 R [円]
# ------------------------------------------------------------
revenue_per_block_jpy = btc_jpy * reward
# 例：reward = 6.25, btc_jpy = 3,676,342.41 のとき
#     revenue_per_block_jpy ≒ 22,977,140 円 （10分あたりの売上）

# ------------------------------------------------------------
# 2. 電力単価 5 円/kWh の場合
# ------------------------------------------------------------

price_5yen_per_kwh = 5.0  # [円/kWh]

# 収入 R とちょうど同じだけ電気代がかかる電力量 E [kWh]
#   E_5yen = R / p_5
energy_kwh_5yen = revenue_per_block_jpy / price_5yen_per_kwh

# 規模感を分かりやすくするために GWh（10^6 kWh）に換算
energy_gwh_5yen = energy_kwh_5yen / 1_000_000.0

puts "電力単価 5 円/kWh のときに収入と一致する消費電力量:"
puts "  E_5yen = #{energy_kwh_5yen} kWh （10分あたり）"
puts "         = #{energy_gwh_5yen} GWh"

# ------------------------------------------------------------
# 3. 電力単価 10 円/kWh の場合
# ------------------------------------------------------------

price_10yen_per_kwh = 10.0  # [円/kWh]

# 同様に、収入と等しくなる電力量 [kWh]
#   E_10yen = R / p_10
energy_kwh_10yen = revenue_per_block_jpy / price_10yen_per_kwh

# GWh に換算
energy_gwh_10yen = energy_kwh_10yen / 1_000_000.0

puts "電力単価 10 円/kWh のときに収入と一致する消費電力量:"
puts "  E_10yen = #{energy_kwh_10yen} kWh （10分あたり）"
puts "          = #{energy_gwh_10yen} GWh"

# ------------------------------------------------------------
# 4. 「10分あたり」という点について
# ------------------------------------------------------------
# ここで求めた E_5yen, E_10yen は「1ブロック ≒ 10分」の期間に
# 消費してよい電力量（kWh）であり、
# 「1ブロックあたりの損益分岐点の電力量」を意味する。
#
# 平均電力（kW）として見たい場合は、
#
#   P = E / (10分) = E / (1/6 時間) = 6E [kW]
#
# と変換できる。
#
# ただし問題文は「消費電力量 (kWh)」と明記しているので、
# 上の E_5yen, E_10yen を答えとするのが自然である。
#
# またコメントにある通り、
#   「この消費量はマイニング競争に参加する一つのプレーヤーが費やす電力」
# を表す前提であり、ネットワーク全体の消費電力ではない点にも注意。