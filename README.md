# Network Client

[![Gem Version](https://badge.fury.io/rb/network-client.svg)](https://rubygems.org/gems/network-client)
[![Gem](https://img.shields.io/gem/dt/network-client.svg?colorB=8b0000)](https://rubygems.org/gems/network-client)
[![Build Status](https://app.travis-ci.com/abarrak/network-client.svg?token=6srXbW1inBqbcVxZhTbQ&branch=master)](https://app.travis-ci.com/abarrak/network-client)
[![Test Coverage](https://api.codeclimate.com/v1/badges/bb30437b8d29917d0bd6/test_coverage)](https://codeclimate.com/github/abarrak/network-client/test_coverage)
[![Maintainability](https://api.codeclimate.com/v1/badges/bb30437b8d29917d0bd6/maintainability)](https://codeclimate.com/github/abarrak/network-client/maintainability)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'network-client'
```

And then execute:

```sh
$ bundle
```

Or install the gem directly:

```sh
$ gem install network-client
```

## Usage

#### Making JSON requests
Given this client set up:

```ruby
require "network-client"

client = Network::Client.new(endpoint: 'https://jsonplaceholder.typicode.com')
```

We can perform the following requests:

  * **GET**

  ```ruby
  client.get '/todos/10'
  
  #=> #<struct Network::Client::Response code=200, body={"userId"=>1, "id"=>10, "title"=>"illo est ...", "completed"=>true}>
  ```

  * **POST**

  ```ruby
  client.post '/todos', params: { title: 'foo bar', completed: 'false', userId: 1 }.to_json

  #=> #<struct Network::Client::Response code=201, body={"title"=>"foo bar", "completed"=>false, "userId"=>1, "id"=>201}>
  ```

  * **PATCH**

  ```ruby
  client.patch '/todos/10', params: { title: 'new title' }.to_json

  #=> #<struct Network::Client::Response code=200, body={"userId"=>1, "id"=>10, "title"=>"new title", "completed"=>true}>
  ```

  * **PUT**

  ```ruby
    client.put '/todos/43', params: { completed: false }.to_json

    #=> #<struct Network::Client::Response code=200, body={"completed"=>false, "id"=>43}> 
  ```

  * **DELETE**

  ```ruby
  client.delete '/todos/25'

  #=> #<struct Network::Client::Response code=200, body={}>
  ```

#### Returned Response

As appears in previous examples, the returned value of each successful request is a `Response` struct. 
It holds the response's HTTP code and body parsed as JSON.

```ruby
response = client.get '/posts/30'
response.code  #=> 200
response.body  #=> { "userId"=>3, "id"=>30, "title"=>"a quo magni similique perferendis", "body"=>"alias dolor cumque ..." }
```

#### Setting Request Headers
Since this is mainly JSON web client, `Accept` and `Content-Type` headers are set to json by default.

You can override them and set extra headers during initialization by providing `headers:` argument:

```ruby
headers = { 'X-SPECIAL-KEY' => '123456' }
client = Network::Client.new(endpoint: 'https://api.example.com', headers: headers)
```

Or on request basis with the `headers:` argument too:

```ruby
client.get 'posts/', headers: { 'X-SPECIAL-KEY' => '123456' }
```

#### HTTP Authentication

  1. **Basic:**
  ```ruby
  # using `username` and `password` named parameters when initialized:

  client = Network::Client.new(endpoint: 'https://api.example.com',
                               username: 'ABC', 
                               password: '999')
  client.username  #=> "ABC"
  client.password  #=> "999"

  # or via `#set_basic_auth`:

  client.set_basic_auth('John Doe', '112233')
  client.username  #=> "John Doe"
  client.password  #=> "112233"
  ```

  2. **OAuth Bearer:**
  ```ruby
  client.set_bearer_auth(token: 'e08f7739c3abb78c')
  client.bearer_token
  #=> "e08f7739c3abb78c"
  ```

  3. **Token Based:**
  ```ruby
  client.set_token_auth(header_value: 'Token token=sec_key_aZcNRzoCMpmdMEP4OEeDUQ==')
  client.auth_token_header
  #=> "Token token=sec_key_aZcNRzoCMpmdMEP4OEeDUQ=="
  ```

#### Customizing User Agent
You can set the user agent header during initialization:

```ruby
client = Network::Client.new(endpoint: 'https://maps.googleapis.com', user_agent: 'App Service')
client.user_agent  #=> "App Service"
```

Or later on via `#set_user_agent` method:

```ruby
client.set_user_agent('Gateway Server')
client.user_agent  #=> "Gateway Server"
```

The default user agent is `Network Client`.

#### Retry and Error Handling
Set the `tries:` named argument to define the number of tries when request fails with one of the retryable errors.

```ruby
client = Network::Client.new(endpoint: 'https://api.foursquare.com', tries: 3)
client.tries  #=> 3
```

The default `#tries` is 2.

To retrieve or extend the list of triable errors through `#errors_to_recover`:

```ruby
client.errors_to_recover

#=> [Net::HTTPTooManyRequests, Net::HTTPServerError, Net::ProtocolError, Net::HTTPBadResponse,Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNREFUSED, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError, SocketError]

client.errors_to_recover << Net::HTTPRequestTimeOut

#=> [Net::HTTPTooManyRequests, Net::HTTPServerError, Net::ProtocolError, Net::HTTPBadResponse,Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNREFUSED, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError, SocketError, Net::HTTPRequestTimeOut]
```

The list of `errors_to_propagate` takes precedence over `errors_to_recover`, and they are not retried.

You can retrieve them for rescue in your application layer, and extend them too.

```ruby
client.errors_to_propagate
#=> [Net::HTTPRequestURITooLong, Net::HTTPMethodNotAllowed]

client.errors_to_propagate << Net::HTTPNotAcceptable
#=> [Net::HTTPRequestURITooLong, Net::HTTPMethodNotAllowed, Net::HTTPNotAcceptable]
```

*Be careful not to add ancestor error class (higher in the inheritance chain) as it will prevent any of it's descendant classes from getting retried. Unless this is an intended behavior, of course.*

#### Logger
When `Rails` is in scope, it's logger will be used by default.

If not, then it defaults to a fallback logger that writes to `STDOUT`.

Additionally, you can override with your custom logger by supplying block to `#set_logger` like so:

```ruby
client = Network::Client.new(endpoint: 'https://api.foursquare.com')

client.set_logger { Logger.new(STDERR) }
client.logger
#=> #<Logger:0x007fb3cd136d38 @progname=nil, @level=0, @default_formatter=#<Logger::Formatter:0x007fb3cd136d10 @datetime_format=nil>, @formatter=nil, @logdev=#<Logger::LogDevice:0x007fb3cd136c98 @shift_size=nil, @shift_age=nil, @filename=nil, @dev=#<IO:<STDERR>>, @mon_owner=nil, @mon_count=0, @mon_mutex=#<Thread::Mutex:0x007fb3cd136c70>>>
```

## Documentation
For more details, please refer to [the API documentation](http://www.rubydoc.info/gems/network-client/2.0.1/Network/Client).

## Contributing
Bug reports and pull requests are very much appreciated at [Github](https://github.com/abarrak/network-client).

  - Fork The repository.
  - Create a branch with the fix or feature name.
  - Make your changes (with test or README changes/additions if applicable).
  - Push changes to the created branch.
  - Create an Pull Request.
  - That's it!


## License
[MIT](http://opensource.org/licenses/MIT).
