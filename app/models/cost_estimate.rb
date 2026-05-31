# バイト数 → GB / 円 のコスト換算を担う純粋 PORO（`*Service` 禁止のため models 配下）。
#
# 換算の定義（プロジェクト統一）:
# - GB は 2 進（GiB, 1 GB = 1024^3 bytes）で表示する（BigQuery コンソールの表示と揃える）。
# - 円は「1 TB = 1000 GB」単価（`yen_per_tb`）で計算する: yen = gb * yen_per_tb / 1000。
#
# バイト ↔ GB の相互変換は `CostEstimate` のクラスメソッドに集約し、
# 接続の上限入力（GB 入力 → bytes 保存）など他箇所からも参照する（換算の一元化）。
class CostEstimate
  BYTES_PER_GB = 1024**3        # 1 GiB
  GB_PER_TB = 1000             # 円単価は 1 TB = 1000 GB
  GB_ROUND = 2                  # GB 表示の小数桁
  YEN_ROUND = 2                 # 円表示の小数桁

  def initialize(bytes:, yen_per_tb:)
    @bytes = bytes.to_i
    @yen_per_tb = yen_per_tb
  end

  # `{ gb: Float, yen: Float }` を返す。
  def estimate
    gb = self.class.bytes_to_gb(@bytes)
    yen = (gb * @yen_per_tb.to_f / GB_PER_TB).round(YEN_ROUND)
    { gb: gb, yen: yen }
  end

  # バイト → GB（GiB, 小数 GB_ROUND 桁に丸め）。
  def self.bytes_to_gb(bytes)
    (bytes.to_f / BYTES_PER_GB).round(GB_ROUND)
  end

  # GB（GiB）→ バイト（整数）。blank は nil（= 上限なし）を返す。
  def self.gb_to_bytes(gb)
    return nil if gb.nil? || gb.to_s.strip.empty?

    (gb.to_f * BYTES_PER_GB).round
  end
end
