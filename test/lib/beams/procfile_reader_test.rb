# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/beams/procfile_reader"

class Beams::ProcfileReaderTest < ActiveSupport::TestCase
  # --- .parse ---
  test "returns name-to-command hash for valid entries" do
    content = "web: bundle exec thrust bin/rails server\nworker: bundle exec bin/jobs\n"
    result = Beams::ProcfileReader.parse(content)
    assert_equal({
      "web" => "bundle exec thrust bin/rails server",
      "worker" => "bundle exec bin/jobs"
    }, result)
  end

  test "handles commands containing colons" do
    content = "web: env KEY=val:extra bundle exec rails s\n"
    result = Beams::ProcfileReader.parse(content)
    assert_equal "env KEY=val:extra bundle exec rails s", result["web"]
  end

  test "ignores blank lines" do
    content = "web: cmd_a\n\nworker: cmd_b\n"
    result = Beams::ProcfileReader.parse(content)
    assert_equal %w[web worker], result.keys.sort
  end

  test "ignores comment lines" do
    content = "# this is a comment\nweb: cmd\n"
    result = Beams::ProcfileReader.parse(content)
    assert_equal({ "web" => "cmd" }, result)
  end

  test "returns empty hash for empty content" do
    assert_equal({}, Beams::ProcfileReader.parse(""))
  end
end
