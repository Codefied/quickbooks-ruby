describe Quickbooks::Service::BaseService do

  it ".is_json" do
    construct_service :invoice
    expect(@service.is_json?).to be false
    construct_service :tax_service
    expect(@service.is_json?).to be true
  end

  describe "#url_for_query" do
    shared_examples "encoding the query correctly" do |domain|
      # Assert on the decoded query rather than the escaped string: whether a space
      # encodes as "+" or "%20" depends on Faraday::Utils.default_space_encoding, which
      # oauth2 2.x flips globally. Both forms are equivalent to the QBO API.
      it "correctly encodes the query" do
        subject.realm_id = 1234
        query = "SELECT * FROM Customer where Name = 'John'"

        uri = URI(subject.url_for_query(query))

        expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq("https://#{domain}/v3/company/1234/query")
        expect(URI.decode_www_form(uri.query).to_h["query"]).to eq("#{query} STARTPOSITION 1 MAXRESULTS 20")
      end
    end

    context "with the production API" do
      it_behaves_like "encoding the query correctly", Quickbooks::Service::BaseService::BASE_DOMAIN
    end

    context "with the sandbox API" do
      around do |example|
        Quickbooks.sandbox_mode = true
        example.run
        Quickbooks.sandbox_mode = false
      end
      it_behaves_like "encoding the query correctly", Quickbooks::Service::BaseService::SANDBOX_DOMAIN
    end

    it "raises an error if there is not realm id" do
      expect{subject.url_for_query("")}.to raise_error(Quickbooks::MissingRealmError)
    end
  end

  describe 'constructor' do
    before do
      construct_compact_service :base_service
    end

    it "correctly initializes with an access_token and realm" do
      expect(@service.company_id).to eq("9991111222")
      expect(@service.oauth).not_to be_nil
    end
  end

  describe 'check_response' do
    before do
      construct_service :base_service
    end

    it "should throw request exception with no options" do
      xml = fixture('generic_error.xml')
      response = Struct.new(:code, :plain_body).new(400, xml)
      expect { @service.send(:check_response, response) }.to raise_error(Quickbooks::IntuitRequestException)
    end

    it "should parse all the error fields" do
      xml = fixture('item_name_too_long_error.xml')
      response = Struct.new(:code, :plain_body).new(400, xml)
      expect { @service.send(:check_response, response, :request => xml) }.to raise_error { |error|
        expect(error.type).to eq "ValidationFault"
        expect(error.code).to eq "2050"
        expect(error.element).to eq "Name"
        expect(error.detail).to eq "String length specified does not match the supported length. Min:0 Max:100 supported. Supplied length:103"
        expect(error.message).to include "String length is either shorter or longer than supported by specification"
        expect(error.message).to include "String length specified does not match the supported length. Min:0 Max:100 supported. Supplied length:103"
      }
    end

    it "should add request xml to request exception" do
      xml = fixture('generic_error.xml')
      xml2 = fixture('customer.xml')
      response = Struct.new(:code, :plain_body).new(400, xml)
      begin
        @service.send(:check_response, response, :request => xml2)
      rescue Quickbooks::IntuitRequestException => ex
        expect(ex.request_xml).to eq(xml2)
      end
    end

    it "should raise AuthorizationFailure on HTTP 401" do
      xml = fixture('generic_error.xml')

      response = Struct.new(:code, :plain_body).new(401, xml)
      expect { @service.send(:check_response, response) }.to raise_error(Quickbooks::AuthorizationFailure)
    end

    it "should raise Forbidden on HTTP 403" do
      xml = fixture('generic_error.xml')

      response = Struct.new(:code, :plain_body).new(403, xml)
      expect { @service.send(:check_response, response) }.to raise_error(Quickbooks::Forbidden)
    end

    it "should raise ThrottleExceeded on HTTP 403 with appropriate message" do
      xml = fixture('throttle_exceeded_error.xml')

      response = Struct.new(:code, :plain_body).new(403, xml)
      expect { @service.send(:check_response, response) }.to raise_error(Quickbooks::ThrottleExceeded)
    end

    it "should raise NotFound on HTTP 404" do
      html = <<-HTML
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html>
  <head>
    <title>404 Not Found</title>
  </head>
  <body>
    <h1>Not Found</h1>
    <p>The requested URL /v3/company/1413511890/query was not found on this server.</p>
  </body>
</html>
      HTML

      response = Struct.new(:code, :plain_body).new(404, html)
      expect { @service.send(:check_response, response) }.to raise_error(Quickbooks::NotFound)
    end

    it "should raise NotFound on HTTP 404" do
      html = <<-HTML
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html>
  <head>
    <title>413 Request Entity Too Large</title>
  </head>
  <body>
    <h1>Request Entity Too Large</h1>
    The requested resource<br />
    /v3/company/123145730715194/batch<br />
    does not allow request data with POST requests, or the amount of data provided in
    the request exceeds the capacity limit.
  </body>
</html>
      HTML

      response = Struct.new(:code, :plain_body).new(413, html)
      expect { @service.send(:check_response, response) }.to raise_error(Quickbooks::RequestTooLarge)
    end

    it "should raise TooManyRequests on HTTP 429 with appropriate message" do
      xml = fixture('too_many_requests_error.xml')
      message = Nokogiri::XML::Document.parse(xml) do |config|
        config.noblanks
      end.css('Message').text

      response = Struct.new(:code, :plain_body).new(429, xml)
      expect { @service.send(:check_response, response) }.to raise_error(Quickbooks::TooManyRequests, message)
    end

    it "should raise ServiceUnavailable on HTTP 502, 503 and 504" do
      xml = fixture('generic_error.xml')

      response = Struct.new(:code, :plain_body).new(502, xml)
      expect { @service.send(:check_response, response) }.to raise_error(Quickbooks::ServiceUnavailable)

      response = Struct.new(:code, :plain_body).new(503, xml)
      expect { @service.send(:check_response, response) }.to raise_error(Quickbooks::ServiceUnavailable)

      response = Struct.new(:code, :plain_body).new(504, xml)
      expect { @service.send(:check_response, response) }.to raise_error(Quickbooks::ServiceUnavailable)
    end
  end

  it "Correctly handled an IntuitRequestException" do
    construct_service :base_service
    xml = fixture("customer_duplicate_error.xml")
    response = Struct.new(:plain_body, :code).new(xml, 400)
    expect{ @service.send(:check_response, response) }.to raise_error(Quickbooks::IntuitRequestException, /is already using this name/)
  end

  context 'logging' do
    let(:assortment) { [nil, 1, Object.new, [], {foo: 'bar'}] }

    before do
      construct_service :vendor
      stub_http_request(:get, @service.url_for_query, ["200", "OK"], fixture("vendors.xml"))
    end

    it "should not log by default" do
      expect(Quickbooks.logger).not_to receive(:info)
      @service.query
    end

    it "should not condense logs by default" do
      expect(Quickbooks.condense_logs?).to be false
    end

    it "should log if Quickbooks.log = true" do
      Quickbooks.log = true
      obj = double('obj', :to_xml => '<test/>')
      expect_any_instance_of(Nokogiri::XML::Document).to receive(:to_xml) { |_| obj.to_xml }
      expect(obj).to receive(:to_xml).once # will only called once on a get request, twice on a post
      expect(Quickbooks.logger).to receive(:info).exactly(10)
      @service.query
      Quickbooks.log = false
    end

    it "should log if Quickbooks.log = true but not prettyprint the xml" do
      Quickbooks.log = true
      Quickbooks.log_xml_pretty_print = false
      expect_any_instance_of(Nokogiri::XML::Document).not_to receive(:to_xml)
      expect(Quickbooks.logger).to receive(:info).exactly(10)
      @service.query
      Quickbooks.log = false
      Quickbooks.log_xml_pretty_print = true
    end

    it 'should log once for request and once for response if Quickbooks.condense_logs = true' do
      Quickbooks.log = true
      Quickbooks.condense_logs = true
      obj = double('obj', :to_xml => '<test/>')
      expect_any_instance_of(Nokogiri::XML::Document).to receive(:to_xml) { |_| obj.to_xml }
      expect(obj).to receive(:to_xml).once # will only called once on a get request, twice on a post
      expect(Quickbooks.logger).to receive(:info).exactly(2)
      @service.query
      Quickbooks.log = false
      Quickbooks.condense_logs = false
    end

    it "log_xml should handle a non-xml string" do
      assortment.each do |e|
        expect{ Quickbooks::Service::BaseService.new.log_xml(e) }.to_not raise_error
      end
    end

    it "log_xml should handle a non-xml string with pretty printing turned off" do
      Quickbooks.log_xml_pretty_print = false
      assortment.each do |e|
        expect{ Quickbooks::Service::BaseService.new.log_xml(e) }.to_not raise_error
      end
      Quickbooks.log_xml_pretty_print = true
    end
  end

  describe "request hooks" do
    # Assert on the RequestInfo the hook receives rather than on captured stdout: the
    # printed form depends on Ruby's Hash#inspect spacing and on
    # Faraday::Utils.default_space_encoding (which oauth2 2.x flips globally), neither
    # of which this behaviour is about.
    let(:expected_query) { "SELECT * FROM Vendor STARTPOSITION 1 MAXRESULTS 20" }
    let(:expected_headers) do
      {
        "Content-Type" => "application/xml",
        "Accept" => "application/xml",
        "Accept-Encoding" => "gzip, deflate"
      }
    end

    before do
      construct_service :vendor
      stub_http_request(:get, @service.url_for_query, %w[200 OK], fixture("vendors.xml"))
    end

    context "with before_request" do
      it "calls before_request with the request info" do
        captured = nil
        @service.before_request = proc { |request_info| captured = request_info }

        @service.query

        expect(captured.method).to eq(:get)
        expect(captured.body).to eq({})
        expect(captured.headers).to include(expected_headers)
        expect(URI.decode_www_form(URI(captured.url).query).to_h["query"]).to eq(expected_query)
      end
    end

    context "with after_request" do
      it "calls after_request with the request info and the response body" do
        captured = nil
        captured_response = nil
        @service.after_request = proc do |request_info, response|
          captured = request_info
          captured_response = response
        end

        @service.query

        expect(captured.method).to eq(:get)
        expect(captured.headers).to include(expected_headers)
        expect(captured.headers).to include("Authorization" => "Bearer token")
        expect(captured_response).to eq(fixture("vendors.xml"))
      end
    end

    context "with around_request" do
      it "wraps the request and returns the response to the caller" do
        events = []
        @service.around_request = proc do |request_info, &block|
          events << [:before, request_info.method]
          response = block.call
          events << [:after, response.body]
          response
        end

        @service.query

        expect(events.first).to eq([:before, :get])
        expect(events.last).to eq([:after, fixture("vendors.xml")])
      end
    end
  end
end
