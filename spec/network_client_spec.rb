require "network-client"

describe NetworkClient::Client do
  describe "Class normal behavior" do
    let(:google) { "https://www.google.com" }

    before do
    end

    context "Initialization" do
      it "generates a class of same type" do
        instance = NetworkClient::Client.new(endpoint: google)
        expect(instance).to be_kind_of(NetworkClient::Client)
      end
    end
  end
end
