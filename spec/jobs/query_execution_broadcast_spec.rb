require "rails_helper"

# ジョブの Turbo Streams ブロードキャスト（SolidCable）の実体を検証する。
# 購読先は @query（同一クエリの複数ウィンドウで結果を受け取れる・司令塔決定）で、
# target "query_result" を置き換える。
RSpec.describe "QueryExecutionJob.broadcast_result" do
  let(:query) { create(:query, sql_body: "SELECT 1") }

  it "replaces query_result on the query stream with the result partial on success" do
    execution = create(:query_execution, :succeeded, query: query)
    execution.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 1 ] ])
    execution.save!

    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    QueryExecutionJob.broadcast_result(execution)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      query,
      hash_including(target: "query_result", partial: "query_executions/result")
    )
  end

  it "replaces query_result with the error partial on failure" do
    execution = create(:query_execution, :failed, query: query)

    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    QueryExecutionJob.broadcast_result(execution)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      query,
      hash_including(target: "query_result", partial: "query_executions/error")
    )
  end
end
