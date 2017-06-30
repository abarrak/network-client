require 'stringio'
require 'dotenv/load'
require 'network-client'
require 'factories/factories'

describe NetworkClient::Client do
  describe "Initialization and Normal Behavior" do
    subject(:client) { NetworkClient::Client.new(endpoint: 'https://api.github.com', tries: 3) }

    it "generates functioning instance" do
      is_expected.to be_kind_of(NetworkClient::Client)
      expect(subject.tries).to eq(3)
      [:get, :post, :put, :delete].each { |m| is_expected.to respond_to(m) }

      home_page = client.get '/users/abarrak'
      expect(home_page.code).to eq(200)
      expect(home_page.body).not_to be_empty
      expect(home_page.body.keys).to include('login', 'id', 'url', 'html_url')
      expect(home_page.body['html_url']).to eq('https://github.com/abarrak')
    end

    it "has default headers set" do
      expect(subject.default_headers).to be_kind_of(Hash)
      expect(subject.default_headers).to include('accept'       => 'application/json',
                                                 'Content-Type' => 'application/json')
    end

    it "makes requests" do
      # Quotes API has limit of 10 requests per hour .. just run this on Travis only.
      if ENV['CI']
        client = NetworkClient::Client.new(endpoint: 'https://quotes.rest/')
        response = client.get('/qod.json', { category: 'inspire' })
        expect(response.code).to eq(200)
        expect(response.body).not_to be_empty
        expect(quotes = response.body['contents']['quotes']).to be_kind_of(Array)
        expect(quotes.first).to include({ 'title' => 'Inspiring Quote of the day' })
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

    example "#put" do
      gist_id = last_gist_id
      zero_content = { 'Content-Length' => '0' }
      response = client.put "/gists/#{@gist_id}/star?access_token=#{token}", nil, zero_content
      expect(response.code).to eq(204)
      expect(response.body).to be_nil

      # Dobule check that gist is starred ..
      response = client.get "/gists/#{@gist_id}/star?access_token=#{token}"
      expect(response.code).to eq(204)
    end

    example "#delete" do
      gist_id = last_gist_id
      response = client.delete "/gists/#{@gist_id}?access_token=#{token}"
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
      expect(created = gists.body.first).to include({ 'description' => 'Network Client Test' })
      expect(@gist_id = created['id']).not_to be_empty
    end
  end

  example_group "Normal HTML form functionality" do
    example "#post_form" do
      expect{
        NetworkClient::Client.new(endpoint: 'https://google.com').post_form nil
      }.to raise_error(NotImplementedError)
    end

    example "#put_form" do
      expect{
        NetworkClient::Client.new(endpoint: 'https://google.com').put_form nil
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
    let(:base_url)      { 'https://api.github.com' }
    let(:sample_base)   { [base_url, "#{base_url}/", "#{base_url}:8080" ].sample }
    let(:github_client) { NetworkClient::Client.new endpoint: sample_base }
    let(:access_hash)   { { 'access_token' => ENV.fetch('GITHUB_OAUTH_TOKEN') } }

    specify "endpint with no path or empty path" do
      path = [nil, '', '   '].sample
      res = github_client.get path, access_hash
      expect(res.code).to eq(200)
      expect(res.body.keys).to include('user_url', 'feeds_url', 'gists_url')
    end

    specify "endpint with improper or proper path" do
      path = ['emojis', '/emojis'].sample
      res = github_client.get path, access_hash
      expect(res.code).to eq(200)
      expect(res.body.keys).to include('+1', 'smile', '2nd_place_medal')
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
