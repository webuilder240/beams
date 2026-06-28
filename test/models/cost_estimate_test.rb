require "test_helper"

class CostEstimateTest < ActiveSupport::TestCase
  # --- #estimate ---
  test "converts 5 GiB at ¥950/TB to { gb: 5.0, yen: 4.75 }" do
    # GB は 1 GiB = 1024^3 bytes、円は 1 TB = 1000 GB 単価（gb * yen_per_tb / 1000）。
    # 5 GiB = 5 * 1024^3 = 5_368_709_120 bytes → 5.0 GB / 5.0 * 950 / 1000 = ¥4.75
    result = CostEstimate.new(bytes: 5_368_709_120, yen_per_tb: 950).estimate
    assert_equal 5.0, result[:gb]
    assert_equal 4.75, result[:yen]
  end

  test "returns zero for zero bytes" do
    result = CostEstimate.new(bytes: 0, yen_per_tb: 950).estimate
    assert_equal({ gb: 0.0, yen: 0.0 }, result)
  end

  test "computes 1000 GB (= 1 TB) at ¥950/TB as ¥950" do
    bytes = 1000 * (1024**3)
    result = CostEstimate.new(bytes: bytes, yen_per_tb: 950).estimate
    assert_equal 1000.0, result[:gb]
    assert_equal 950.0, result[:yen]
  end

  test "accepts a decimal yen_per_tb" do
    bytes = 1000 * (1024**3)
    result = CostEstimate.new(bytes: bytes, yen_per_tb: BigDecimal("950.0")).estimate
    assert_equal 950.0, result[:yen]
  end

  test "rounds GB to a small number of decimals" do
    # 1.5 GiB
    bytes = (1.5 * (1024**3)).to_i
    result = CostEstimate.new(bytes: bytes, yen_per_tb: 950).estimate
    assert_equal 1.5, result[:gb]
  end
end
