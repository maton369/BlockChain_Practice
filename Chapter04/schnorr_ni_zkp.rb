# ファイル名: schnorr_ni_zkp.rb

require 'ecdsa'
require 'securerandom'
require 'digest'

# ============================================================
# 非対話型 Schnorr ゼロ知識証明 (Fiat–Shamir 変換)
# ============================================================
# 設定:
# - 楕円曲線: secp256k1（Bitcoin と同じ曲線）
# - 群: この楕円曲線上の位数 n を持つ加法群
# - 生成元 G: generator（基準となる点）
#
# 証明したい主張:
#   「公開鍵 X に対して，その離散対数 x（X = xG）を知っている」
#
# Schnorr 証明（対話型）を Fiat–Shamir 変換によって非対話型化する:
#
#  1. 証明者（Prover）:
#     - 秘密鍵 x を持つ（公開鍵 X = xG は検証者が知っている）
#     - ランダムな r ∈ [0, n-1] を選ぶ
#     - コミットメント R = rG を計算
#     - ハッシュ関数 H を用いてチャレンジ e を自己生成する:
#
#         e = H(R, X, m) mod n
#
#       （m はオプションのメッセージ：署名のように「何に対する証明か」を紐付ける）
#
#     - 応答 s を計算:
#
#         s = r + e·x  (mod n)
#
#     - 証明として (R, s) を検証者に渡す。
#
#  2. 検証者（Verifier）:
#     - 公開鍵 X，メッセージ m，証明 (R, s) を受け取る
#     - 同じルールで e を再計算:
#
#         e = H(R, X, m) mod n
#
#     - 次をチェック:
#
#         sG == R + eX
#
#       左辺:
#         sG = (r + e·x)G = rG + e·xG = R + eX
#
#       右辺:
#         R + eX
#
#       が常に一致するため，正しい x を知っていれば常に検証に通る。
#       逆に，x を知らないまま (R, s) をでっち上げるのは，
#       ハッシュ H のランダムオラクル仮定の下で困難とみなされる。
#
# ここでは H として SHA-256 を用い，
#   e = SHA256(R.x || X.x || m) mod n
# の形でスカラーに落とし込む。
# （実装簡略のため x座標とメッセージ文字列のみを使っている）
# ============================================================

# 楕円曲線として secp256k1 を利用
EC = ECDSA::Group::Secp256k1

# 位数 n（曲線上の生成元 G が生成するサブグループのサイズ）
N  = EC.order

# ベースポイント（生成元） G
G_POINT  = EC.generator

# ------------------------------------------------------------
# ハッシュ関数 H: (R, X, m) → e (スカラー)
# ------------------------------------------------------------
# - ポイント r_point, pubkey の x座標とメッセージ message を文字列化し連結して SHA-256。
# - 出力 256 ビットを n で割った余りをチャレンジ e として用いる。
#   こうすることで e が [0, n-1] の範囲に収まる。
# ------------------------------------------------------------
def schnorr_challenge(r_point, pubkey, message)
  # r_point.x, pubkey.x, message を結合してハッシュ入力にする
  input_str = "#{r_point.x}-#{pubkey.x}-#{message}"
  digest    = Digest::SHA256.hexdigest(input_str).to_i(16)
  digest % N
end

# ------------------------------------------------------------
# 証明者 (Prover) 側の処理
# ------------------------------------------------------------
# 入力:
#   - secret_key: 秘密鍵 x ∈ [1, n-1]
#   - message   : 証明を紐付けたい任意のメッセージ（文字列）
#
# 出力:
#   - public_key: 公開鍵 X = xG
#   - proof     : { R: r_point, s: s } というハッシュ
#
# 理論的に行っていること:
#   1. ランダム r ∈ [0, n-1] を選ぶ
#   2. R = rG を計算（コミットメント）
#   3. e = H(R, X, m) を計算（Fiat–Shamir による自己チャレンジ）
#   4. s = r + e·x (mod n) を計算
# ------------------------------------------------------------
def schnorr_prove(secret_key, message = "")
  # 秘密鍵 x
  x = secret_key

  # 公開鍵 X = xG
  public_key = G_POINT * x

  # ランダムな r を生成（0〜n-1 の一様乱数）
  r_scalar = SecureRandom.random_number(N - 1)

  # コミットメント R = rG
  r_point = G_POINT * r_scalar

  # チャレンジ e = H(R, X, m)
  e = schnorr_challenge(r_point, public_key, message)

  # 応答 s = r + e·x (mod n)
  s = (r_scalar + e * x) % N

  # 検証者に渡す証明は (R, s) と公開鍵 X, メッセージ m
  proof = { R: r_point, s: s }

  [public_key, proof]
end

# ------------------------------------------------------------
# 検証者 (Verifier) 側の処理
# ------------------------------------------------------------
# 入力:
#   - public_key: 公開鍵 X
#   - proof    : { R: r_point, s: s }
#   - message   : 証明が紐付いているメッセージ（Prover と一致している必要）
#
# 判定:
#   - sG == R + eX が成り立てば true（検証成功）
#   - そうでなければ false（検証失敗）
# ------------------------------------------------------------
def schnorr_verify(public_key, proof, message = "")
  r_point = proof[:R]
  s       = proof[:s]

  # チャレンジ e を再計算（Fiat–Shamir の前提として同じ手続きで計算）
  e = schnorr_challenge(r_point, public_key, message)

  # 左辺: sG
  left  = G_POINT * s

  # 右辺: R + eX
  right = r_point + public_key * e

  left == right
end

# ============================================================
# デモ実行
# ============================================================
if __FILE__ == $0
  # 証明したいメッセージ（省略して "" でも良い）
  message = "I know the discrete log of this public key."

  # 証明者の秘密鍵 x を乱数で生成（1〜n-1）
  secret_key = SecureRandom.random_number(N - 1)

  # 証明者が非対話型 Schnorr 証明 (R, s) を生成
  public_key, proof = schnorr_prove(secret_key, message)

  # 検証者が (X, proof, message) を受け取り，検証を実施
  ok = schnorr_verify(public_key, proof, message)

  puts "公開鍵 X: (#{public_key.x}, #{public_key.y})"
  puts "証明 (R, s):"
  puts "  R = (#{proof[:R].x}, #{proof[:R].y})"
  puts "  s = #{proof[:s]}"
  puts
  puts "検証結果: #{ok}"  # => true となるはず
end