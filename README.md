# Network Client

[![Gem Version](https://badge.fury.io/rb/network-client.svg)](https://rubygems.org/gems/network-client)
[![Gem](https://img.shields.io/gem/dt/network-client.svg?colorB=8b0000)](https://rubygems.org/gems/network-client)
[![Build Status](https://travis-ci.org/abarrak/network-client.svg?branch=master)](https://travis-ci.org/abarrak/network-client)
[![Dependency Status](https://gemnasium.com/badges/github.com/abarrak/network-client.svg)](https://gemnasium.com/github.com/abarrak/network-client)
[![Test Coverage](https://codeclimate.com/github/abarrak/network-client/badges/coverage.svg)](https://codeclimate.com/github/abarrak/network-client/coverage)
[![Code Climate](https://lima.codeclimate.com/github/abarrak/network-client/badges/gpa.svg)](https://lima.codeclimate.com/github/abarrak/network-client)
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

  * *GET*

  * *POST*

  * *PATCH*

  * *PUT*

  * *DELETE*

#### Setting Request Headers

#### HTTP Authentication

  1. **Basic**

  2. **OAuth Bearer**

  3. **Token**

#### Customizing User Agent

You can set the user agent header during initalization:
```ruby
client = Network::Client.new(endpoint: 'https://maps.googleapis.com', user_agent: 'App Service')
client.user_agnet #=> "App Service"
```

Or later on via `#set_user_agent` method:

```ruby
client.set_user_agent('Gatewya Server')
client.user_agnet #=> "Gatewya Server"
```

#### Retry and Error Handling

#### Logger


## Documentation 

For more details refer to [the API documentation](http://www.rubydoc.info/gems/network-client/2.0.0/Network/Client).

## Contributing

Bug reports and pull requests are very much appreciated at [Github](https://github.com/abarrak/network-client).

  - Fork The repository.
  - Create a branch with the fix or feature name.
  - Make your changes (with test or README changes/additions if applicable).
  - Push changes to the created branch
  - Create an Pull Request
  - That's it!


## License

[MIT](http://opensource.org/licenses/MIT).
