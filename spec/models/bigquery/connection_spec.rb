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

  describe "encryption of service_account_json" do
    it "returns the original plaintext via the attribute reader" do
      json = '{"type":"service_account","project_id":"p"}'
      connection = create(:bigquery_connection, service_account_json: json)
      expect(connection.reload.service_account_json).to eq(json)
    end

    it "does not store the plaintext in the raw SQLite row" do
      secret = "SUPER_SECRET_PRIVATE_KEY_MARKER"
      json = %({"type":"service_account","private_key":"#{secret}"})
      connection = create(:bigquery_connection, service_account_json: json)

      raw = ActiveRecord::Base.connection.select_value(
        "SELECT service_account_json FROM bigquery_connections WHERE id = #{connection.id}"
      )
      expect(raw).not_to include(secret)
      expect(raw).not_to eq(json)
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
end
