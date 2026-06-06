# frozen_string_literal: true

require "rails_helper"
require "erb"

# ONCE デプロイで bin/jobs が起動直後に
#   "Solid Queue is configured to use N threads but the database connection pool is 5"
# と吐いて即終了する事故が起きたため、queue.yml の workers.threads 合計と
# database.yml の production:queue の pool が整合していることを設定レベルで担保する。
# threads 数を queue.yml 側で増やすと、このテストが連動して max_connections の不足を検知する。
RSpec.describe "production queue DB connection pool" do
  let(:database_config) do
    YAML.safe_load(ERB.new(File.read(Rails.root.join("config/database.yml"))).result, aliases: true)
  end

  let(:queue_config) do
    YAML.safe_load(ERB.new(File.read(Rails.root.join("config/queue.yml"))).result, aliases: true)
  end

  let(:queue_pool) do
    queue = database_config.fetch("production").fetch("queue")
    Integer(queue["pool"] || queue["max_connections"])
  end

  let(:required_threads) do
    workers = queue_config.fetch("production").fetch("workers")
    workers.sum { |w| Integer(w["threads"]) }
  end

  it "has enough connections for every SolidQueue worker thread" do
    # SolidQueue は workers の threads 合計に加えてディスパッチャ等の内部スレッドも
    # connection を要求する。2 本程度の余裕を必ず確保しておく。
    expect(queue_pool).to be >= required_threads + 2,
      "queue DB pool (#{queue_pool}) < SolidQueue workers threads (#{required_threads}) + 2 余裕。" \
      "config/database.yml の production:queue の pool/max_connections を引き上げてください。"
  end
end
