require "rails_helper"

RSpec.describe Bigquery::Connection, type: :model do
  describe "table mapping (namespace)" do
    it "maps to the bigquery_connections table via table_name_prefix" do
      expect(described_class.table_name).to eq("bigquery_connections")
    end
  end

  describe "validations" do
    it "is valid with the factory" do
      expect(build(:bigquery_connection)).to be_valid
    end

    it "requires a name" do
      connection = build(:bigquery_connection, name: nil)
      expect(connection).not_to be_valid
      expect(connection.errors[:name]).to be_present
    end

    it "requires a project_id" do
      connection = build(:bigquery_connection, project_id: nil)
      expect(connection).not_to be_valid
      expect(connection.errors[:project_id]).to be_present
    end

    it "rejects a project_id with invalid characters" do
      connection = build(:bigquery_connection, project_id: "invalid project!")
      expect(connection).not_to be_valid
      expect(connection.errors[:project_id]).to be_present
    end

    it "accepts a project_id with alphanumerics and hyphens" do
      connection = build(:bigquery_connection, project_id: "my-project-123")
      expect(connection).to be_valid
    end

    it "requires service_account_json" do
      connection = build(:bigquery_connection, service_account_json: nil)
      expect(connection).not_to be_valid
      expect(connection.errors[:service_account_json]).to be_present
    end

    it "rejects service_account_json that is not parseable JSON" do
      connection = build(:bigquery_connection, service_account_json: "{not valid json")
      expect(connection).not_to be_valid
      expect(connection.errors[:service_account_json]).to be_present
    end

    it "rejects service_account_json that is valid JSON but not an object" do
      connection = build(:bigquery_connection, service_account_json: "[1, 2, 3]")
      expect(connection).not_to be_valid
      expect(connection.errors[:service_account_json]).to be_present
    end

    it "allows a nil maximum_bytes_billed (= no limit)" do
      connection = build(:bigquery_connection, maximum_bytes_billed: nil)
      expect(connection).to be_valid
    end

    it "allows a positive maximum_bytes_billed" do
      connection = build(:bigquery_connection, maximum_bytes_billed: 1_000_000)
      expect(connection).to be_valid
    end

    it "rejects a zero maximum_bytes_billed" do
      connection = build(:bigquery_connection, maximum_bytes_billed: 0)
      expect(connection).not_to be_valid
      expect(connection.errors[:maximum_bytes_billed]).to be_present
    end

    it "rejects a negative maximum_bytes_billed" do
      connection = build(:bigquery_connection, maximum_bytes_billed: -1)
      expect(connection).not_to be_valid
      expect(connection.errors[:maximum_bytes_billed]).to be_present
    end
  end

  describe "service_account_json storage (plaintext)" do
    # トピック27（AR Encryption 撤廃）以降、`service_account_json` は SQLite に平文で保存する。
    # ホスト側のディスク暗号化・ファイルパーミッション・`/storage` ボリュームの
    # アクセス制御に保護を委ねる方針（docs/adr/0002-drop-active-record-encryption.md）。
    it "returns the original plaintext via the attribute reader" do
      json = '{"type":"service_account","project_id":"p"}'
      connection = create(:bigquery_connection, service_account_json: json)
      expect(connection.reload.service_account_json).to eq(json)
    end

    it "stores the plaintext as-is in the raw SQLite row" do
      secret = "SUPER_SECRET_PRIVATE_KEY_MARKER"
      json = %({"type":"service_account","private_key":"#{secret}"})
      connection = create(:bigquery_connection, service_account_json: json)

      raw = ActiveRecord::Base.connection.select_value(
        "SELECT service_account_json FROM bigquery_connections WHERE id = #{connection.id}"
      )
      expect(raw).to eq(json)
      expect(raw).to include(secret)
    end
  end

  describe "#bigquery" do
    let(:connection) do
      build(
        :bigquery_connection,
        project_id: "my-project-123",
        service_account_json: '{"type":"service_account","project_id":"my-project-123"}'
      )
    end

    it "returns a Google::Cloud::Bigquery client built from project_id and credentials" do
      fake_client = instance_double(Google::Cloud::Bigquery::Project)

      expect(Google::Cloud::Bigquery).to receive(:new).with(
        project_id: "my-project-123",
        credentials: { "type" => "service_account", "project_id" => "my-project-123" }
      ).and_return(fake_client)

      expect(connection.bigquery).to eq(fake_client)
    end

    it "memoizes the client" do
      fake_client = instance_double(Google::Cloud::Bigquery::Project)
      allow(Google::Cloud::Bigquery).to receive(:new).and_return(fake_client)

      connection.bigquery
      connection.bigquery
      expect(Google::Cloud::Bigquery).to have_received(:new).once
    end
  end

  describe "#test_connection" do
    let(:connection) { build(:bigquery_connection) }
    let(:fake_client) { instance_double(Google::Cloud::Bigquery::Project) }

    before do
      allow(connection).to receive(:bigquery).and_return(fake_client)
    end

    context "when both dry-run and datasets.list succeed" do
      it "returns success: true" do
        allow(fake_client).to receive(:query_job).with("SELECT 1", dryrun: true)
        allow(fake_client).to receive(:datasets).and_return([])

        expect(connection.test_connection).to eq({ success: true })
      end

      it "treats an empty dataset list as success" do
        allow(fake_client).to receive(:query_job).with("SELECT 1", dryrun: true)
        allow(fake_client).to receive(:datasets).and_return([])

        result = connection.test_connection
        expect(result[:success]).to be(true)
      end

      it "runs the dry-run query without billing (dry_run: true)" do
        allow(fake_client).to receive(:query_job).with("SELECT 1", dryrun: true)
        allow(fake_client).to receive(:datasets).and_return([])

        connection.test_connection
        expect(fake_client).to have_received(:query_job).with("SELECT 1", dryrun: true)
      end
    end

    context "when the dry-run is denied for bigquery.jobs.create" do
      it "extracts the missing permission and returns failure" do
        error = Google::Cloud::PermissionDeniedError.new(
          "Access Denied: Project p: User does not have bigquery.jobs.create permission in project p."
        )
        allow(fake_client).to receive(:query_job).and_raise(error)
        allow(fake_client).to receive(:datasets).and_return([])

        result = connection.test_connection
        expect(result[:success]).to be(false)
        expect(result[:missing_permissions]).to include("bigquery.jobs.create")
        expect(result[:message]).to be_present
      end
    end

    context "when datasets.list is denied for bigquery.datasets.list" do
      it "extracts the missing permission and returns failure" do
        allow(fake_client).to receive(:query_job).with("SELECT 1", dryrun: true)
        error = Google::Cloud::PermissionDeniedError.new(
          "Access Denied: Project p: User does not have bigquery.datasets.list permission."
        )
        allow(fake_client).to receive(:datasets).and_raise(error)

        result = connection.test_connection
        expect(result[:success]).to be(false)
        expect(result[:missing_permissions]).to include("bigquery.datasets.list")
      end
    end

    context "when multiple permissions are missing across both checks" do
      it "aggregates the missing permissions" do
        jobs_error = Google::Cloud::PermissionDeniedError.new(
          "User does not have bigquery.jobs.create permission in project p."
        )
        datasets_error = Google::Cloud::PermissionDeniedError.new(
          "User does not have bigquery.datasets.list permission."
        )
        allow(fake_client).to receive(:query_job).and_raise(jobs_error)
        allow(fake_client).to receive(:datasets).and_raise(datasets_error)

        result = connection.test_connection
        expect(result[:missing_permissions]).to contain_exactly(
          "bigquery.jobs.create", "bigquery.datasets.list"
        )
      end
    end

    context "when a non-permission error occurs" do
      it "returns failure with the error message and no missing permissions" do
        allow(fake_client).to receive(:query_job).and_raise(
          Google::Cloud::Error.new("network unreachable")
        )
        allow(fake_client).to receive(:datasets).and_return([])

        result = connection.test_connection
        expect(result[:success]).to be(false)
        expect(result[:missing_permissions]).to eq([])
        expect(result[:message]).to include("network unreachable")
      end
    end
  end

  describe "maximum_bytes_billed_gb (GB 入力 → bytes 保存の仮想属性)" do
    it "writes GB input as bytes into maximum_bytes_billed" do
      connection = build(:bigquery_connection)
      connection.maximum_bytes_billed_gb = "10"
      # 10 GiB = 10 * 1024^3
      expect(connection.maximum_bytes_billed).to eq(10 * (1024**3))
    end

    it "reads the bytes back as GB" do
      connection = build(:bigquery_connection, maximum_bytes_billed: 5 * (1024**3))
      expect(connection.maximum_bytes_billed_gb).to eq(5.0)
    end

    it "treats a blank GB input as no limit (nil)" do
      connection = build(:bigquery_connection, maximum_bytes_billed: 10**10)
      connection.maximum_bytes_billed_gb = ""
      expect(connection.maximum_bytes_billed).to be_nil
    end

    it "returns nil GB when no limit is set" do
      connection = build(:bigquery_connection, maximum_bytes_billed: nil)
      expect(connection.maximum_bytes_billed_gb).to be_nil
    end

    it "accepts a fractional GB value" do
      connection = build(:bigquery_connection)
      connection.maximum_bytes_billed_gb = "0.5"
      expect(connection.maximum_bytes_billed).to eq((0.5 * (1024**3)).round)
    end
  end

  describe "#over_limit?" do
    it "is false when maximum_bytes_billed is nil (no limit)" do
      connection = build(:bigquery_connection, maximum_bytes_billed: nil)
      expect(connection.over_limit?(10**12)).to be(false)
    end

    it "is false when bytes_processed is within the limit" do
      connection = build(:bigquery_connection, maximum_bytes_billed: 1_000)
      expect(connection.over_limit?(999)).to be(false)
    end

    it "is false when bytes_processed equals the limit (boundary)" do
      connection = build(:bigquery_connection, maximum_bytes_billed: 1_000)
      expect(connection.over_limit?(1_000)).to be(false)
    end

    it "is true when bytes_processed exceeds the limit" do
      connection = build(:bigquery_connection, maximum_bytes_billed: 1_000)
      expect(connection.over_limit?(1_001)).to be(true)
    end
  end

  describe "#job_options" do
    it "includes maximum_bytes_billed when a limit is set" do
      connection = build(:bigquery_connection, maximum_bytes_billed: 5_000)
      expect(connection.job_options).to eq({ maximum_bytes_billed: 5_000 })
    end

    it "is empty when no limit is set (nil)" do
      connection = build(:bigquery_connection, maximum_bytes_billed: nil)
      expect(connection.job_options).to eq({})
    end
  end

  describe "#dry_run_job" do
    let(:connection) { build(:bigquery_connection, maximum_bytes_billed: 5_000) }
    let(:fake_client) { instance_double(Google::Cloud::Bigquery::Project) }

    before { allow(connection).to receive(:bigquery).and_return(fake_client) }

    it "creates a dry-run job carrying the connection's maximum_bytes_billed" do
      job = instance_double(Google::Cloud::Bigquery::Job)
      allow(fake_client).to receive(:query_job)
        .with("SELECT 1", dryrun: true, maximum_bytes_billed: 5_000)
        .and_return(job)

      expect(connection.dry_run_job("SELECT 1")).to eq(job)
    end

    it "omits maximum_bytes_billed when no limit is set" do
      connection = build(:bigquery_connection, maximum_bytes_billed: nil)
      allow(connection).to receive(:bigquery).and_return(fake_client)
      job = instance_double(Google::Cloud::Bigquery::Job)
      allow(fake_client).to receive(:query_job)
        .with("SELECT 1", dryrun: true).and_return(job)

      expect(connection.dry_run_job("SELECT 1")).to eq(job)
    end
  end

  describe "schema cache (SolidCache)" do
    include ActiveSupport::Testing::TimeHelpers

    let(:connection) { create(:bigquery_connection) }
    let(:fake_client) { instance_double(Google::Cloud::Bigquery::Project) }

    # BigQuery のレスポンスをスタブする double 群を組み立てる。
    # datasets.list → dataset.tables → INFORMATION_SCHEMA.COLUMNS の3段。
    def stub_bigquery!(columns: default_columns)
      table = instance_double(
        Google::Cloud::Bigquery::Table, table_id: "events", type: "TABLE"
      )
      dataset = instance_double(
        Google::Cloud::Bigquery::Dataset,
        dataset_id: "analytics", name: "Analytics", tables: [ table ]
      )
      allow(connection).to receive(:bigquery).and_return(fake_client)
      allow(fake_client).to receive(:datasets).and_return([ dataset ])
      allow(fake_client).to receive(:query).and_return(columns)
    end

    def default_columns
      [
        { table_name: "events", column_name: "user_id",
          data_type: "STRING", is_nullable: "YES", ordinal_position: 1 },
        { table_name: "events", column_name: "amount",
          data_type: "INT64", is_nullable: "NO", ordinal_position: 2 }
      ]
    end

    before do
      Rails.cache.clear
    end

    describe "#sync_schema!" do
      it "fetches datasets, tables and columns from BigQuery and writes the cache" do
        stub_bigquery!

        structure = connection.sync_schema!

        expect(fake_client).to have_received(:datasets)
        expect(fake_client).to have_received(:query)

        dataset = structure[:datasets].first
        expect(dataset[:dataset_id]).to eq("analytics")
        expect(dataset[:name]).to eq("Analytics")

        table = dataset[:tables].first
        expect(table[:table_id]).to eq("events")
        expect(table[:table_type]).to eq("TABLE")

        columns = table[:columns]
        expect(columns.map { |c| c[:column_name] }).to eq([ "user_id", "amount" ])
        expect(columns.first).to include(
          column_name: "user_id", data_type: "STRING",
          is_nullable: true, ordinal_position: 1
        )
        expect(columns.second[:is_nullable]).to be(false)
      end

      it "stores the structure in Rails.cache under the connection-scoped key" do
        stub_bigquery!

        connection.sync_schema!

        cached = Rails.cache.read("bigquery:schema:#{connection.id}")
        expect(cached).to be_present
        expect(cached[:datasets].first[:dataset_id]).to eq("analytics")
        expect(cached[:fetched_at]).to be_present
      end
    end

    describe "#cached_schema" do
      it "syncs on the first access and serves from cache on the second" do
        stub_bigquery!

        first = connection.cached_schema
        second = connection.cached_schema

        expect(first[:datasets].first[:dataset_id]).to eq("analytics")
        expect(second).to eq(first)
        # 2 回呼んでも BigQuery アクセスは 1 回だけ（2 回目はキャッシュ）
        expect(fake_client).to have_received(:datasets).once
      end

      it "re-fetches after the 24h TTL expires" do
        stub_bigquery!

        connection.cached_schema

        travel 25.hours do
          connection.cached_schema
        end

        expect(fake_client).to have_received(:datasets).twice
      end

      it "serves from cache within the TTL (1 hour later)" do
        stub_bigquery!

        connection.cached_schema

        travel 1.hour do
          connection.cached_schema
        end

        expect(fake_client).to have_received(:datasets).once
      end
    end

    describe "#sync_schema!(force: true)" do
      it "re-fetches and overwrites even when a fresh cache exists" do
        stub_bigquery!

        connection.cached_schema
        connection.sync_schema!(force: true)

        expect(fake_client).to have_received(:datasets).twice
      end
    end
  end
end
