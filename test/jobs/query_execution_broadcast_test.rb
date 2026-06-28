# frozen_string_literal: true

require "test_helper"

# ジョブの Turbo Streams ブロードキャスト（SolidCable）の実体を検証する。
# 購読先は @query（同一クエリの複数ウィンドウで結果を受け取れる・司令塔決定）で、
# target "query_result" を置き換える。
class QueryExecutionBroadcastTest < ActiveJob::TestCase
  # Turbo::StreamsChannel の broadcast_* を全てキャプチャするための共通スタブ。
  # ブロック内で yield し、呼び出し履歴を返す。
  def capture_broadcasts
    replaces = []
    prepends = []
    Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*args, **kwargs) { replaces << [ args, kwargs ] }) do
      Turbo::StreamsChannel.stub(:broadcast_prepend_to, ->(*args, **kwargs) { prepends << [ args, kwargs ] }) do
        yield
      end
    end
    { replaces: replaces, prepends: prepends }
  end

  test "replaces query_result on the query stream with the result partial on success" do
    query = create_query(sql_body: "SELECT 1")
    execution = create_succeeded_query_execution(query: query)
    execution.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 1 ] ])
    execution.save!

    captured = capture_broadcasts do
      QueryExecutionJob.broadcast_result(execution)
    end

    match = captured[:replaces].find do |args, kwargs|
      args.first == query && kwargs[:target] == "query_result" && kwargs[:partial] == "query_executions/result"
    end
    assert match, "expected broadcast_replace_to with query/query_result/result partial. got: #{captured[:replaces].inspect}"
  end

  test "replaces query_result with the error partial on failure" do
    query = create_query(sql_body: "SELECT 1")
    execution = create_failed_query_execution(query: query)

    captured = capture_broadcasts do
      QueryExecutionJob.broadcast_result(execution)
    end

    match = captured[:replaces].find do |args, kwargs|
      args.first == query && kwargs[:target] == "query_result" && kwargs[:partial] == "query_executions/error"
    end
    assert match, "expected broadcast_replace_to with query/query_result/error partial. got: #{captured[:replaces].inspect}"
  end

  test "prepends a new history row to query_history_rows on the query stream (トピック17)" do
    query = create_query(sql_body: "SELECT 1")
    execution = create_succeeded_query_execution(query: query)
    execution.store_result([ { "name" => "n", "type" => "INTEGER" } ], [ [ 1 ] ])
    execution.save!

    captured = capture_broadcasts do
      QueryExecutionJob.broadcast_result(execution)
    end

    match = captured[:prepends].find do |args, kwargs|
      args.first == query && kwargs[:target] == "query_history_rows" && kwargs[:partial] == "query_executions/history_row"
    end
    assert match, "expected broadcast_prepend_to with query/query_history_rows/history_row partial. got: #{captured[:prepends].inspect}"
  end
end
