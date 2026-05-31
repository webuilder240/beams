require "rails_helper"

RSpec.describe CostEstimate, type: :model do
  describe "#estimate" do
    it "converts 5 GiB at ¥950/TB to { gb: 5.0, yen: 4.75 }" do
      # GB は 1 GiB = 1024^3 bytes、円は 1 TB = 1000 GB 単価（gb * yen_per_tb / 1000）。
      # 5 GiB = 5 * 1024^3 = 5_368_709_120 bytes → 5.0 GB / 5.0 * 950 / 1000 = ¥4.75
      result = described_class.new(bytes: 5_368_709_120, yen_per_tb: 950).estimate
      expect(result[:gb]).to eq(5.0)
      expect(result[:yen]).to eq(4.75)
    end

    it "returns zero for zero bytes" do
      result = described_class.new(bytes: 0, yen_per_tb: 950).estimate
      expect(result).to eq({ gb: 0.0, yen: 0.0 })
    end

    it "computes 1000 GB (= 1 TB) at ¥950/TB as ¥950" do
      bytes = 1000 * (1024**3)
      result = described_class.new(bytes: bytes, yen_per_tb: 950).estimate
      expect(result[:gb]).to eq(1000.0)
      expect(result[:yen]).to eq(950.0)
    end

    it "accepts a decimal yen_per_tb" do
      bytes = 1000 * (1024**3)
      result = described_class.new(bytes: bytes, yen_per_tb: BigDecimal("950.0")).estimate
      expect(result[:yen]).to eq(950.0)
    end

    it "rounds GB to a small number of decimals" do
      # 1.5 GiB
      bytes = (1.5 * (1024**3)).to_i
      result = described_class.new(bytes: bytes, yen_per_tb: 950).estimate
      expect(result[:gb]).to eq(1.5)
    end
  end
end
