require "dotenv/load"
require "network-client"

describe NetworkClient::Client do
  describe "Initialization and Normal Behavior" do
    subject(:client) { NetworkClient::Client.new(endpoint: 'https://api.github.com') }

    it "generates functioning client instance" do
      is_expected.to be_kind_of(NetworkClient::Client)
      is_expected.to be_a(NetworkClient::Client)
      expect(subject.tries).to eq(2)
      [:get, :post, :put, :delete].each { |m| is_expected.to respond_to(m) }

      home_page = client.get '/users/abarrak'
      expect(home_page.code.to_i).to eq(200)
      expect(home_page.body).not_to be_empty
      expect(home_page.body.keys).to include('login', 'id', 'url', 'html_url')
      expect(home_page.body['html_url']).to eq('https://github.com/abarrak')
    end

    it "has default headers set" do
      expect(subject.default_headers).to be_kind_of(Hash)
      expect(subject.default_headers).to include('accept'       => 'application/json')
      expect(subject.default_headers).to include('Content-Type' => 'application/json')
    end

    it "has proper initialized logger" do
      expect(subject.logger).to be_kind_of(Logger)
      [:debug, :info, :warn, :error, :fatal].each { |m| expect(subject.logger).to respond_to(m) }
    end

    it "detects and use Rails logger" do
    end

    it "can have customized logger" do
      subject.set_logger do
        l = Logger.new(STDERR)
        l.level = Logger::INFO
        l
      end
      expect(subject.logger.level).to eq(Logger::INFO)
      expect(subject.logger.instance_variable_get(:@logdev).dev).to be(STDERR)
    end

    it "encodes passed query parameters correctly in GET request" do
    end

    it "handles different shapes of urls provided" do
    end
  end

  example_group "JSON web client functionality out of the box" do
    example '#get' do
      client = NetworkClient::Client.new(endpoint: 'https://quotes.rest/')
      response = client.get('/qod.json', { category: 'inspire' })

      expect(response.code).to eq('200')
      expect(response.body).not_to be_empty
      expect(response.body).to have_key('contents')
      expect(response.body['contents']).to have_key('quotes')
      expect(quotes = response.body['contents']['quotes']).to be_kind_of(Array)
      expect(quotes.first).to include({ 'title' => 'Inspiring Quote of the day' })
    end

    example "#post" do
    end

    example "#put" do
    end

    example "#delete" do
    end
  end

  example_group "Normal HTML form functionality" do
    example "#post_form" do
    end

    example "#put_form" do
    end
  end

  context "Errors and Failures" do
    specify "handling #errors_to_recover_by_retry list by retry @tries times then re-raise" do
    end

    specify "handling #errors_to_recover_by_propogate list by stoping call and re-raise" do
    end
  end
end
