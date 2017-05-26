require "network-client"

describe NetworkClient::Client do
  describe "Initialization and Normal Behavior" do
    subject(:client) { NetworkClient::Client.new(endpoint: 'https://api.moyasar.com') }

    it "generates a functioning client instance" do
      is_expected.to be_kind_of(NetworkClient::Client)
      [:get, :post, :put, :delete].each { |m| is_expected.to respond_to(m) }

      home_page = client.get '/v1/payments/'
      expect(home_page.code.to_i).to eq(401)
      expect(home_page.body).not_to be_empty
      expect(home_page.body.keys).to include('type', 'message', 'errors')
      expect(home_page.body['type']).to eq('authentication_error')
    end

    it "has a default headers set" do
    end

    it "has a proper initialized logger" do
    end
  end

  example_group "JSON web client functionality out of the box" do
  end
end
