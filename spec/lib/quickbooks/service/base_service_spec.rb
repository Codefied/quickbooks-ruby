describe Quickbooks::Service::BaseService do

  it ".is_json" do
    construct_service :invoice
    expect(@service.is_json?).to be false
    construct_service :tax_service
    expect(@service.is_json?).to be true
  end

  describe "#url_for_query" do
    shared_examples "encoding the query correctly" do |domain|
      it "builds a correctly-encoded, decodable query URL" do
        subject.realm_id = 1234
        query = "SELECT * FROM Customer where Name = 'John'"
        url = subject.url_for_query(query)

        expect(url).to start_with("https://#{domain}/v3/company/1234/query?")
        # Assert on the decoded query so the test is independent of the encoder's
        # choice of "+" vs "%20" for spaces (that representation changed in Faraday 2).
        expect(URI.decode_www_form(URI(url).query).to_h["query"]).to start_with(query)
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
    before do
      construct_service :vendor
      stub_http_request(:get, @service.url_for_query, %w[200 OK], fixture("vendors.xml"))
    end

    # Assert on the structured RequestInfo the hooks receive, not on exact stdout.
    # The previous string assertions were coupled to Faraday's query encoding
    # ("+" vs "%20") and Ruby's Hash#inspect format ("=>" vs " => " in Ruby 3.4),
    # both of which change across versions.
    it "invokes before_request with the request info" do
      captured = nil
      @service.before_request = ->(request_info) { captured = request_info }

      @service.query

      expect(captured.method).to eq(:get)
      expect(captured.url).to include("/query?")
      expect(URI.decode_www_form(URI(captured.url).query).to_h["query"]).to include("SELECT * FROM Vendor")
      expect(captured.headers).to include("Content-Type" => "application/xml")
    end

    it "invokes after_request with the request info and the raw response body" do
      body = nil
      @service.after_request = ->(_request_info, response) { body = response }

      @service.query

      expect(body).to include("<IntuitResponse")
      expect(body).to include("<Vendor ")
    end

    it "invokes around_request, wrapping the call and returning the response" do
      events = []
      @service.around_request = proc do |_request_info, &block|
        events << :before
        response = block.call
        events << :after
        response
      end

      @service.query

      expect(events).to eq(%i[before after])
    end
  end
end
