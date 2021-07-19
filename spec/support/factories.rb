GithubGist = Struct.new :description, :public, :files do
  def to_json
    { description: description, public: public, files: files }.to_json
  end
end

FactoryBot.define do
  factory :github_gist do
    description { 'Network Client Test' }
    public { :true }
    files {{
      'test_text_file.txt' => {
        'content' =>  'this simple text file is maid for testing purposes only ! .. '
      }
    }}
  end
end
