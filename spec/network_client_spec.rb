require "network-client"

describe NetworkClient::Client do
  describe "Initialization and Normal Behavior" do
    let(:moyasar) { "https://moyasar.com" }
    let(:instance) { NetworkClient::Client.new(endpoint: moyasar) }

    before do
    end

    it "generates a class of same type" do
      expect(instance).to be_kind_of(NetworkClient::Client)
    end

    it "fetches moyasar home page successfully" do
      title = "<title>Moyasar · Payment Service Provider in Saudi Arabia</title>"
      home_page = instance.get('/en/')

      expect(home_page.code.to_i).to eq(200)
      expect(home_page.body).not_to be_empty
      expect(home_page.body).to include(title)
    end
  end
end
