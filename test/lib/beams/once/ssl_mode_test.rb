# frozen_string_literal: true

require "test_helper"
require_relative "../../../../lib/beams/once/ssl_mode"

class Beams::Once::SslModeTest < ActiveSupport::TestCase
  # --- #enabled? ---
  test "returns false (SSL disabled) when DISABLE_SSL is 'true'" do
    mode = Beams::Once::SslMode.new(env: { "DISABLE_SSL" => "true" })
    assert_equal false, mode.enabled?
  end

  test "returns true (SSL enabled by default) when DISABLE_SSL is not set" do
    mode = Beams::Once::SslMode.new(env: {})
    assert_equal true, mode.enabled?
  end

  test "returns true (SSL enabled) when DISABLE_SSL is empty string" do
    mode = Beams::Once::SslMode.new(env: { "DISABLE_SSL" => "" })
    assert_equal true, mode.enabled?
  end

  test "returns true (SSL enabled) when DISABLE_SSL is some other string" do
    mode = Beams::Once::SslMode.new(env: { "DISABLE_SSL" => "false" })
    assert_equal true, mode.enabled?
  end

  test "treats arbitrary values as SSL enabled" do
    mode = Beams::Once::SslMode.new(env: { "DISABLE_SSL" => "1" })
    assert_equal true, mode.enabled?
  end

  test "reads from process ENV when env: is not passed" do
    original = ENV["DISABLE_SSL"]
    ENV["DISABLE_SSL"] = "true"
    begin
      mode = Beams::Once::SslMode.new
      assert_equal false, mode.enabled?
    ensure
      ENV["DISABLE_SSL"] = original
    end
  end

  # --- #ssl_options ---
  test "excludes /up from https redirect" do
    mode = Beams::Once::SslMode.new(env: {})
    options = mode.ssl_options
    assert_kind_of Hash, options
    assert_kind_of Hash, options[:redirect]
    exclude = options[:redirect][:exclude]
    assert_kind_of Proc, exclude

    up_request = Struct.new(:path).new("/up")
    other_request = Struct.new(:path).new("/queries")
    assert_equal true, exclude.call(up_request)
    assert_equal false, exclude.call(other_request)
  end

  test "returns ssl_options regardless of DISABLE_SSL value" do
    mode = Beams::Once::SslMode.new(env: { "DISABLE_SSL" => "true" })
    assert_kind_of Hash, mode.ssl_options
    assert_kind_of Proc, mode.ssl_options.dig(:redirect, :exclude)
  end
end
