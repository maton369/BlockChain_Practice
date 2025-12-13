# ファイル名: schnorr_ec_signature.rb

require 'ecdsa'
require 'securerandom'
require 'digest'

# ============================================================
# 楕円曲線 Schnorr 署名の実装（secp256k1）
# ============================================================
# 理論背景（ざっくり）：
#
# - 楕円曲線 secp256k1 上の生成元 G と位数 n を共有する。
# - 秘密鍵 d（スカラー）から公開鍵 P = dG（点）を計算する。
#
# Schnorr 署名（Fiat–Shamir 変換された署名版）は：
#
# [鍵生成]
#   秘密鍵 d ∈ [1, n-1]
#   公開鍵 P = dG
#
# [署名生成（Sign）]
#   入力：メッセージ m, 秘密鍵 d
#   1. ランダム r ∈ [1, n-1] を生成（エフェメラル秘密）
#   2. R = rG を計算（エフェメラル公開鍵）
#   3. チャレンジ e をハッシュから生成：
#        e = H(R, m) もしくは H(R, P, m) を n で割った値
#      （ここでは簡単化して e = SHA256(R.x || m) mod n）
#   4. 応答 s = r + e·d (mod n)
#   5. 署名は (R, s)
#
# [署名検証（Verify）]
#   入力：メッセージ m, 署名 (R, s), 公開鍵 P
#   1. 同じルールで e = H(R, m) を再計算
#   2. sG と R + eP を比較：
#        sG ?= R + eP
#
#   もし署名生成時と同じ d, r, m であれば：
#     sG = (r + e·d)G = rG + e·dG = R + eP
#   となるので常に等式が成立する（完全性）。
#
#   逆に、d を知らずに (R, s) を捏造することは、
#   楕円曲線離散対数問題（ECDLP）の困難さと
#   ハッシュ H をランダムオラクルとみなす仮定のもとで
#   計算困難だと考えられている（安全性）。
# ============================================================

# 楕円曲線として secp256k1 を利用
EC_GROUP = ECDSA::Group::Secp256k1

# 位数 n（生成元 G が生成するサブグループのサイズ）
ORDER_N = EC_GROUP.order

# ベースポイント（生成元） G
BASE_POINT = EC_GROUP.generator

# ------------------------------------------------------------
# チャレンジ e = H(R, m) mod n を計算する補助関数
# ------------------------------------------------------------
# - R.x とメッセージ m を連結して SHA-256 を取り、整数化して n で割る。
# - 本来は R の (x, y) や公開鍵 P もハッシュに含める設計が望ましいが、
#   ここでは最小限の教材用として R.x と m のみを使う。
# ------------------------------------------------------------
def schnorr_challenge(r_point, message)
  # ハッシュ入力を "R.x || m" として文字列連結
  input_str = r_point.x.to_s + message
  digest    = Digest::SHA256.hexdigest(input_str).to_i(16)
  digest % ORDER_N
end

# ------------------------------------------------------------
# 楕円曲線 Schnorr 署名生成関数
# ------------------------------------------------------------
# 引数:
#   secret_key : 秘密鍵 d（スカラー，1〜n-1 の整数）
#   message    : 署名対象メッセージ（文字列）
#
# 戻り値:
#   [public_key, signature]
#   - public_key : 公開鍵 P（楕円曲線上の点）
#   - signature  : { R: R, s: s } というハッシュ
#                  R: 楕円曲線上の点
#                  s: 整数（スカラー）
# ------------------------------------------------------------
def schnorr_sign(secret_key, message)
  # 秘密鍵 d
  d = secret_key

  # 公開鍵 P = dG
  public_key = BASE_POINT * d

  # エフェメラル秘密 r をランダムに選ぶ（1〜n-1）
  r = SecureRandom.random_number(ORDER_N - 1)

  # エフェメラル公開鍵 R = rG
  r_point = BASE_POINT * r

  # チャレンジ e = H(R, m) mod n
  e = schnorr_challenge(r_point, message)

  # 応答 s = r + e·d (mod n)
  s = (r + e * d) % ORDER_N

  # 署名は (R, s)
  signature = { R: r_point, s: s }

  [public_key, signature]
end

# ------------------------------------------------------------
# 楕円曲線 Schnorr 署名検証関数
# ------------------------------------------------------------
# 引数:
#   public_key : 公開鍵 P（楕円曲線上の点）
#   message    : メッセージ m（署名時と同じ文字列である必要がある）
#   signature  : { R: R, s: s } 形式の署名
#
# 戻り値:
#   true / false で検証成功 / 失敗を返す
#
# 検証条件:
#   sG == R + eP   （e = H(R, m)）
# ------------------------------------------------------------
def schnorr_verify(public_key, message, signature)
  r_point = signature[:R] # 署名から R を取り出す
  s       = signature[:s] # 署名から s を取り出す

  # メッセージと R からチャレンジ e を再計算
  e = schnorr_challenge(r_point, message)

  # 左辺: sG
  left  = BASE_POINT * s

  # 右辺: R + eP
  right = r_point + public_key * e

  left == right
end

# ============================================================
# デモ実行
# ============================================================
if __FILE__ == $0
  # 署名対象のメッセージ
  message = "世界さんこんにちは"

  # 秘密鍵 d をランダム生成（1〜n-1）
  secret_key = SecureRandom.random_number(ORDER_N - 1)

  # 署名生成
  public_key, signature = schnorr_sign(secret_key, message)

  # 検証
  ok = schnorr_verify(public_key, message, signature)

  # 結果表示（数値は大きいので「理論的に何が起きているか」に注目）
  puts "=== Schnorr 署名デモ（secp256k1）==="
  puts "メッセージ m: #{message}"
  puts
  puts "公開鍵 P:"
  puts "  Px = #{public_key.x}"
  puts "  Py = #{public_key.y}"
  puts
  puts "署名 (R, s):"
  puts "  R.x = #{signature[:R].x}"
  puts "  R.y = #{signature[:R].y}"
  puts "  s   = #{signature[:s]}"
  puts
  puts "検証結果: #{ok}"  # => true となるはず
end