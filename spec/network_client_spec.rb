require 'stringio'
require 'dotenv/load'
require 'network-client'
require 'factories/factories'

describe NetworkClient::Client do
  describe "Initialization and Normal Behavior" do
    subject(:client) { NetworkClient::Client.new(endpoint: 'https://deckofcardsapi.com', tries: 3) }

    it "generates functioning instance" do
      is_expected.to be_kind_of(NetworkClient::Client)
      expect(subject.tries).to eq(3)
      [:get, :post, :put, :delete].each { |m| is_expected.to respond_to(m) }

      response_payload = client.get '/api/deck/new/shuffle/?deck_count=1'
      expect(response_payload.code).to eq(200)
      expect(response_payload.body).not_to be_empty
      expect(response_payload.body.keys).to include('success', 'deck_id', 'shuffled', 'remaining')
    end

    it "has default headers set" do
      expect(subject.default_headers).to be_kind_of(Hash)
      expect(subject.default_headers).to include('accept'       => 'application/json',
                                                 'Content-Type' => 'application/json')
    end

    it "makes requests" do
      # Quotes API has limit of 10 requests per hour
      client = NetworkClient::Client.new(endpoint: 'https://quotes.rest/')
      client.set_logger { Logger.new(StringIO.new) }

      response = client.get('/qod.json', { category: 'inspire' })
      expect(response.body).not_to be_empty

      if response.code == 200
        expect(quotes = response.body['contents']['quotes']).to be_kind_of(Array)
        expect(quotes.first).to include({ 'title' => 'Inspiring Quote of the day' })
      else
        expect(response.code).to be(429)
        expect(error = response.body['error']).not_to be_empty
        expect(error['message']).to match(/Too Many Requests: Rate limit of 10 requests per hour/)
      end
    end

    it "has proper initialized logger" do
      expect(subject.logger).to be_kind_of(Logger)
      [:debug, :info, :warn, :error, :fatal].each { |m| expect(subject.logger).to respond_to(m) }
    end

    it "detects and use Rails logger" do
      # Stub Rails constant and its logger ..
      rails = Object.new
      rails.define_singleton_method :logger do
        @custom_logger ||= begin
          custom = Logger.new(STDOUT)
          custom.level = Logger::FATAL
          custom
        end
      end
      stub_const 'Rails', rails

      expect(client.logger).to be(rails.logger)
      expect(subject.logger.level).to eq(Logger::FATAL)
      expect(subject.logger.instance_variable_get(:@logdev).dev).to be(STDOUT)
    end

    it "can have customized logger" do
      subject.set_logger { Logger.new(STDERR) }
      expect(subject.logger.level).to eq(Logger::DEBUG)
      expect(subject.logger.instance_variable_get(:@logdev).dev).to be(STDERR)
    end

    context "Retry and Propagate" do
      let(:log_store)  { StringIO.new }
      let(:error_code) { error_code = [429, 500, 502, 503, 504].sample }
      let!(:client)    { NetworkClient::Client.new(endpoint: 'https://httpstat.us', tries: 4) }

      before(:each) { client.set_logger { Logger.new(log_store) } }

      it "has retry feature" do
        response = client.get "/#{error_code}"
        expect(response.code).to be(error_code)
        expect(log_store.string).to match(/Retrying now/)
        expect(log_store.string.scan(/Retrying now/).count).to be(4)
      end

      it "has error propagation support" do
        response = client.get '/405'
        expect(response.code).to be(405)
        expect(log_store.string.scan(/Retrying now/).count).to be(0)
      end
    end

    it "has default user agent" do
      client = NetworkClient::Client.new(endpoint: 'https://opentdb.com')
      expect(client.user_agent).not_to be_empty
      expect(client.user_agent).to eq('network-client gem')
      expect(client.default_headers).to include({ 'User-Agent' => 'network-client gem' })
    end

    it "supports customizing user agent header during or after initialization" do
      user_agent = ['XYZ Service', '', nil].sample

      client = NetworkClient::Client.new(endpoint: 'https://opentdb.com', user_agent: user_agent)
      expect(client.user_agent).to eq(user_agent)
      expect(client.default_headers).to include({ 'User-Agent' => user_agent })
    end
  end

  example_group "JSON web client functionality out of the box", order: :defined do
    let!(:token) { ENV.fetch('GITHUB_OAUTH_TOKEN') }
    let(:user)   { "abarrak" }
    let(:client) { NetworkClient::Client.new(endpoint: 'https://api.github.com') }

    example '#get' do
      response = client.get "/gists/4849a20d2ba89b34b201?access_token=#{token}"
      expect(response.code).to eq(200)
      expect(response.body['description']).to match(/Jim Weirich's "Decoupling from Rails" talk/)
      expect(response.body['files']).not_to be_empty
      expect(response.body['files'].keys).to include('test_induced_design_damage.rb')
    end

    example "#post" do
      gist = FactoryGirl.build(:github_gist)
      response = client.post "/gists?access_token=#{token}", gist.to_json
      expect(response.code).to eq(201)
      expect(response.body).not_to be_empty
      expect(response.body.keys).to include('url', 'id', 'forks', 'commits_url', 'owner')
    end

    example "#patch" do
      gist_id = last_gist_id
      params = { description: 'New description ~' }
      response = client.patch "/gists/#{gist_id}?access_token=#{token}", params.to_json
      expect(response.code).to eq(200)
      expect(response.body).not_to be_empty
      expect(response.body.keys).to include('url', 'id', 'forks', 'commits_url', 'owner')
      expect(response.body['description']).to eq(params[:description])
    end

    example "#put" do
      gist_id = last_gist_id
      zero_content = { 'Content-Length' => '0' }
      response = client.put "/gists/#{gist_id}/star?access_token=#{token}", nil, zero_content
      expect(response.code).to eq(204)
      expect(response.body).to be_nil

      # Dobule check that gist is starred ..
      response = client.get "/gists/#{gist_id}/star?access_token=#{token}"
      expect(response.code).to eq(204)
    end

    example "#delete" do
      gist_id = last_gist_id
      response = client.delete "/gists/#{gist_id}?access_token=#{token}"
      expect(response.code).to eq(204)
      expect(response.body).to be_nil
    end

    example "#get with query parameters" do
      response = client.get "/gists/public", { access_token: token, page: 2, per_page: 20 }
      expect(response.code).to eq(200)
      expect(response.body).to be_kind_of(Array)
      expect(response.body.size).to eq(20)
    end

    def last_gist_id
      gists = client.get "/users/#{user}/gists?access_token=#{token}"
      expect(gists.code).to eq(200)
      expect(gists.body).to be_kind_of(Array)
      expect(created = gists.body.first).not_to be_empty
      expect(gist_id = created['id']).not_to be_empty
      expect(created['description']).to eq('Network Client Test').or eq('New description ~')
      gist_id
    end
  end

  example_group "Normal HTML form functionality" do
    example "#get_html" do
      expect{
        NetworkClient::Client.new(endpoint: 'https://google.com').get_html nil
      }.to raise_error(NotImplementedError)
    end

    example "#post_form" do
      expect{
        NetworkClient::Client.new(endpoint: 'https://google.com').post_form nil
      }.to raise_error(NotImplementedError)
    end
  end

  context "Errors and Failures" do
    let(:log_store) { StringIO.new }

    specify "logging unsuccessful requests" do
      client = NetworkClient::Client.new(endpoint: 'https://quotes.rest')
      client.set_logger { Logger.new(log_store) }

      response = client.get '/not-there-at-all.json'
      expect(response.code).to be(404)
      expect(response.body).not_to be_empty
      expect(response.body['error']['message']).to eq('Not Found')
      expect(log_store.string).to match(/endpoint responded with non-success #{response.code} code/)
    end

    specify "handling json parsing errors" do
      client = NetworkClient::Client.new(endpoint: 'https://www.apple.com')
      client.set_logger { Logger.new(log_store) }

      response = client.get '/mac/'
      expect(response.code).to be(200)
      expect(response.body).to be_a(String)
      expect(log_store.string).to match(/Parsing response body as JSON failed!/)
    end
  end

  describe "handling different shapes of provided urls" do
    specify "endpint with no path or empty path" do
      base = 'http://samples.openweathermap.org'
      url  = [base, "#{base}/", "#{base}:80" ].sample
      path = [nil, '', '   '].sample

      client = NetworkClient::Client.new endpoint: url
      res = client.get path
      expect(res.code).to eq(200)
      expect(res.body.keys).to include('name', 'products')
    end

    specify "endpint with improper or proper path" do
      client = NetworkClient::Client.new endpoint: 'http://api.openweathermap.org'
      path = ['data/2.5/weather', '/data/2.5/weather'].sample
      res = client.get path, { lat: 35, lon: 139, appid: ENV.fetch('OPEN_WEATHERMAP_API') }
      expect(res.code).to eq(200)
      expect(res.body.keys).to include('coord', 'weather', 'main', 'wind', 'clouds')
      expect(res.body['coord']['lat']).to be_within(0.5).of(35)
      expect(res.body['coord']['lon']).to be_within(0.5).of(139)
    end
  end

  describe "HTTP basic Authentication" do
    it "is supported" do
    end
  end

  describe "HTTP Token Authentication" do
    it "is supported" do
    end
  end
end
