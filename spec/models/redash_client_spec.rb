require "rails_helper"

RSpec.describe RedashClient, type: :model do
  let(:source) do
    # SSRF ガードを通すため、Resolv をスタブしてグローバル IP に解決させる。
    allow(Resolv).to receive(:getaddresses).and_return([ "203.0.113.10" ])
    build(:redash_source,
          name: "Test Redash",
          url: "https://redash.example.com",
          api_key: "secret-key-abc")
  end
  let(:client) { described_class.new(source) }

  describe "#list_queries" do
    it "returns parsed JSON for a successful 200 response" do
      body = {
        "count" => 2,
        "page" => 1,
        "page_size" => 25,
        "results" => [
          { "id" => 10, "name" => "Daily users" },
          { "id" => 11, "name" => "Monthly revenue" }
        ]
      }.to_json

      stub = stub_request(:get, "https://redash.example.com/api/queries?page=1&page_size=25")
        .with(headers: { "Authorization" => "Key secret-key-abc" })
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      result = client.list_queries(page: 1, page_size: 25)

      expect(stub).to have_been_requested
      expect(result["count"]).to eq(2)
      expect(result["results"].first["name"]).to eq("Daily users")
    end

    it "raises Unauthorized on 401" do
      stub_request(:get, /redash\.example\.com\/api\/queries/)
        .to_return(status: 401, body: "{}", headers: { "Content-Type" => "application/json" })

      expect { client.list_queries }.to raise_error(RedashClient::Unauthorized)
    end

    it "raises ServerError on 500" do
      stub_request(:get, /redash\.example\.com\/api\/queries/)
        .to_return(status: 500, body: "boom")

      expect { client.list_queries }.to raise_error(RedashClient::ServerError)
    end

    it "raises Timeout when the connection times out" do
      stub_request(:get, /redash\.example\.com\/api\/queries/).to_timeout

      expect { client.list_queries }.to raise_error(RedashClient::Timeout)
    end
  end

  describe "#fetch_query" do
    it "returns parsed JSON for a successful 200 response" do
      body = {
        "id" => 42,
        "name" => "Revenue",
        "query" => "SELECT 1",
        "options" => { "parameters" => [] }
      }.to_json

      stub = stub_request(:get, "https://redash.example.com/api/queries/42")
        .with(headers: { "Authorization" => "Key secret-key-abc" })
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      result = client.fetch_query(42)

      expect(stub).to have_been_requested
      expect(result["id"]).to eq(42)
      expect(result["query"]).to eq("SELECT 1")
    end

    it "raises NotFound on 404" do
      stub_request(:get, "https://redash.example.com/api/queries/999")
        .to_return(status: 404, body: "{}")

      expect { client.fetch_query(999) }.to raise_error(RedashClient::NotFound)
    end

    it "raises Unauthorized on 403" do
      stub_request(:get, "https://redash.example.com/api/queries/42")
        .to_return(status: 403, body: "{}")

      expect { client.fetch_query(42) }.to raise_error(RedashClient::Unauthorized)
    end

    it "raises ServerError if the body is not parseable JSON" do
      stub_request(:get, "https://redash.example.com/api/queries/42")
        .to_return(status: 200, body: "<html>oops</html>")

      expect { client.fetch_query(42) }.to raise_error(RedashClient::ServerError)
    end

    it "raises ArgumentError when id is not an integer-like value" do
      expect { client.fetch_query("not-an-id") }.to raise_error(ArgumentError)
    end
  end

  describe "SSRF guard" do
    # source / client を先に materialize した上で、Resolv スタブを上書きする
    # （`source` の作成過程で Resolv を 203.0.113.10 に上書きしてしまうため、
    # その後に再度スタブする必要がある）。
    before do
      client # materialize source/client
    end

    it "raises ForbiddenURLError without performing HTTP when host resolves to a loopback IP" do
      allow(Resolv).to receive(:getaddresses).and_return([ "127.0.0.1" ])
      stub = stub_request(:get, /redash\.example\.com/)

      expect { client.list_queries }.to raise_error(RedashClient::ForbiddenURLError)
      expect(stub).not_to have_been_requested
    end

    it "raises ForbiddenURLError when host resolves to a private IP" do
      allow(Resolv).to receive(:getaddresses).and_return([ "10.0.0.5" ])
      stub = stub_request(:get, /redash\.example\.com/)

      expect { client.list_queries }.to raise_error(RedashClient::ForbiddenURLError)
      expect(stub).not_to have_been_requested
    end

    it "raises ForbiddenURLError when host resolves to the link-local metadata IP" do
      allow(Resolv).to receive(:getaddresses).and_return([ "169.254.169.254" ])
      stub = stub_request(:get, /redash\.example\.com/)

      expect { client.list_queries }.to raise_error(RedashClient::ForbiddenURLError)
      expect(stub).not_to have_been_requested
    end

    it "raises ForbiddenURLError when the host cannot be resolved" do
      allow(Resolv).to receive(:getaddresses).and_return([])
      stub = stub_request(:get, /redash\.example\.com/)

      expect { client.list_queries }.to raise_error(RedashClient::ForbiddenURLError)
      expect(stub).not_to have_been_requested
    end

    # M1: DNS rebinding 対策。1 回目の resolve で得た安全 IP に接続し、
    # 2 回目以降の resolve（例: メタデータ IP）が結果に影響しないことを検証する。
    it "connects to the IP resolved during the guard (not a later DNS response)" do
      call_count = 0
      allow(Resolv).to receive(:getaddresses) do
        call_count += 1
        call_count == 1 ? [ "203.0.113.10" ] : [ "169.254.169.254" ]
      end

      stub = stub_request(:get, "https://redash.example.com/api/queries?page=1&page_size=25")
        .to_return(status: 200, body: '{"results":[]}', headers: { "Content-Type" => "application/json" })

      client.list_queries(page: 1, page_size: 25)

      expect(stub).to have_been_requested
      # 1 度目の安全 IP にしか接続が行かないこと（メタデータ IP への接続が発生しない）。
      expect(WebMock).not_to have_requested(:get, /169\.254\.169\.254/)
    end
  end

  # M3: ForbiddenURLError の権威は RedashSource 側。
  # RedashClient::ForbiddenURLError は互換 alias として残す。
  describe "ForbiddenURLError alias (M3)" do
    it "is the same class as RedashSource::ForbiddenURLError" do
      expect(RedashClient::ForbiddenURLError).to equal(RedashSource::ForbiddenURLError)
    end
  end

  # S5: build_url 冒頭で base.query を nil クリアしてから組み立てる。
  # source.url に意図しないクエリ（?leak=token）が混入していても流出させない。
  describe "URL query sanitization (S5)" do
    let(:dirty_source) do
      allow(Resolv).to receive(:getaddresses).and_return([ "203.0.113.10" ])
      build(:redash_source,
            name: "Dirty Redash",
            url: "https://redash.example.com/?leak=token",
            api_key: "secret-key-abc")
    end
    let(:dirty_client) { described_class.new(dirty_source) }

    it "drops leak parameters from the source URL before building the request URL" do
      stub = stub_request(:get, "https://redash.example.com/api/queries")
        .with(query: hash_excluding("leak" => "token"))
        .to_return(status: 200, body: '{"results":[]}', headers: { "Content-Type" => "application/json" })

      dirty_client.list_queries(page: 1, page_size: 25)

      expect(stub).to have_been_requested
      expect(WebMock).not_to have_requested(:get, /leak=token/)
    end
  end
end
