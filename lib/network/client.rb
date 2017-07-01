require 'net/http'
require 'openssl'
require 'json'
require 'logger'

module Network
  class Client
    DEFAULT_HEADERS = { 'accept' => 'application/json',
                        'Content-Type' => 'application/json' }.freeze
    # The success response template.
    #
    # Represents the return of rest-like methods holding two values:
    # HTTP response code, and body <em>(parsed as json if request type is json)</em>.
    Response = Struct.new(:code, :body)

    # Stamp in front of each log written by client +@logger+.
    LOG_TAG = '[NETWORK CLIENT]:'.freeze

    attr_reader :username, :password, :default_headers, :logger, :tries, :user_agent,
                :bearer_token, :auth_token_header

    # Error list for retrying strategy.
    # Initially contains common errors encountered usually in net calls.
    attr_accessor :errors_to_recover

    # Error list for stop and propagate strategy.
    # Takes priority over +@errors_to_recover+.
    # Do not assign ancestor error classes here that prevent retry for descendant ones.
    attr_accessor :errors_to_propagate

    ##
    # Construct and prepare client for requests targeting +endpoint+.
    #
    # == Parameters:
    #
    # [*endpoint*] +string+ Uri for the host with schema and port.
    #              any other segment like paths will be discarded.
    # [*tries*] +integer+ to specify how many is to repeat failed calls. Default is 2.
    # [*headers*] +hash+ to contain any common HTTP headers to be set in client calls.
    # [*username*] +string+ for HTTP basic authentication. Applies on all requests. Default to nil.
    # [*password*] +string+ for HTTP basic authentication. Applies on all requests. Default to nil.
    # [*user_agent*] +string+ Specifies the _User-Agent_ header value when making requests.
    # *User-Agent* header value provided within +headers+ parameter in +initialize+ or on one of
    # request methods will take precedence over +user_agent+ parameter.
    #
    # == Example:
    #   require "network-client"
    #
    #   github_client = Network::Client.new(endpoint: 'https://api.github.com')
    #   github_client.get '/emojis'
    #
    #   #=> { "+1": "https://assets-cdn.github.com/images/icons/emoji/unicode/1f44d.png?v7",
    #         "-1": "https://assets-cdn.github.com/images/icons/emoji/unicode/1f44e.png?v7",
    #         ... }
    #
    def initialize(endpoint:, tries: 2, headers: {}, username: nil, password: nil,
                   user_agent: 'network-client gem')
      @uri = URI.parse(endpoint)
      @tries = tries

      set_http_client
      set_default_headers(headers)
      set_basic_auth(username, password)
      set_logger
      define_error_strategies
      set_user_agent(headers['User-Agent'] || user_agent)
      set_bearer_auth
      set_custom_token_auth
    end

    ##
    # Perform a get request on the targeted client +endpoint+.
    #
    # == Parameters:
    # [*path*] +string+ path on client's target host.
    # [*params*] request parameters to be url encoded. Can be +hash+ or pair of values +array+.
    # [*headers*] +hash+ set of http request headers.
    #
    # == Returns:
    # http response data contained in +Response+ struct.
    #
    def get(path, params: {}, headers: {})
      request_json :get, path, params, headers
    end

    ##
    # Perform a post request on the targeted client +endpoint+.
    #
    # == Parameters:
    # [*path*] +string+ path on client's target host.
    # [*params*] +hash+ request parameters to json encoded in request body.
    # [*headers*] +hash+ set of http request headers.
    #
    # == Returns:
    # http response data contained in +Response+ struct.
    #
    def post(path, params: {}, headers: {})
      request_json :post, path, params, headers
    end

    ##
    # Perform a patch request on the targeted client +endpoint+.
    #
    # == Parameters:
    # [*path*] +string+ path on client's target host.
    # [*params*] +hash+ request parameters to json encoded in request body.
    # [*headers*] +hash+ set of http request headers.
    #
    # == Returns:
    # http response data contained in +Response+ struct.
    #
    def patch(path, params: {}, headers: {})
      request_json :patch, path, params, headers
    end

    ##
    # Perform a put request on the targeted client +endpoint+.
    #
    # == Parameters:
    # [*path*] +string+ path on client's target host.
    # [*params*] +hash+ request parameters to json encoded in request body.
    # [*headers*] +hash+ set of http request headers.
    #
    # == Returns:
    # http response data cotained in +Response+ strcut.
    #
    def put(path, params: {}, headers: {})
      request_json :put, path, params, headers
    end

    ##
    # Perform a delete request on the targeted client +endpoint+.
    #
    # == Parameters:
    # [*path*] +string+ path on client's target host.
    # [*params*] +hash+ request parameters to json encoded in request body.
    # [*headers*] +hash+ set of http request headers.
    #
    # == Returns:
    # http response data contained in +Response+ struct.
    #
    def delete(path, params: {}, headers: {})
      request_json :delete, path, params, headers
    end

    def get_html(path, params: {}, headers: {})
      raise NotImplementedError
    end

    def post_form(path, params: {}, headers: {})
      raise NotImplementedError
    end

    ##
    # Sets the client logger object.
    # Execution is yielded to passed +block+ to set, customize, and returning a logger instance.
    #
    # == Returns:
    # +logger+ instance variable.
    #
    def set_logger
      @logger = if block_given?
        yield
      elsif defined?(Rails)
        Rails.logger
      else
        logger = Logger.new(STDOUT)
        logger.level = Logger::DEBUG
        logger
      end
    end

    def set_basic_auth(username, password)
      @username = username.nil? ? '' : username
      @password = password.nil? ? '' : password
    end

    ##
    # Assigns authentication bearer type token for use in standard HTTP authorization header.
    #
    # == Parameters:
    # [*token*] +string+ bearer token value.
    #
    # == Returns:
    # [@bearer_token] +string+ the newly assigned +@bearer_token+ value.
    #
    def set_bearer_auth(token: '')
      @bearer_token = token
    end

    ##
    # Assigns custom authentication token for use in standard HTTP authorization header.
    # This takes precedence over Bearer authentication if both are set.
    #
    # == Parameters:
    # [*header_value*] +string+ full authorization header value. _(e.g. Token token=123)_.
    #
    # == Returns:
    # [@auth_token_header] +string+ the newly assigned +@auth_token_header+ value.
    #
    def set_custom_token_auth(header_value: '')
      @auth_token_header = header_value
    end

    ##
    # Assigns a new +User-Agent+ header to be sent in any subsequent request.
    #
    # == Parameters:
    # [*new_user_agent*] +string+ the user-agent header value.
    #
    # == Returns:
    # [@user_agent] +string+ the newly assigned +User-Agent+ header value.
    #
    def set_user_agent(new_user_agent)
      @user_agent = @default_headers['User-Agent'] = new_user_agent
    end

    private

    def set_http_client
      @http = Net::HTTP.new(@uri.host, @uri.port)
      @http.use_ssl = @uri.scheme == 'https' ? true : false
      @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    def set_default_headers(headers)
      @default_headers = DEFAULT_HEADERS.merge(headers)
    end

    def define_error_strategies
      @errors_to_recover   = [Net::HTTPTooManyRequests,
                              Net::HTTPServerError,
                              Net::ProtocolError,
                              Net::HTTPBadResponse,
                              Net::ReadTimeout,
                              Net::OpenTimeout,
                              Errno::ECONNREFUSED,
                              Errno::ETIMEDOUT,
                              OpenSSL::SSL::SSLError,
                              SocketError]
      @errors_to_propagate = [Net::HTTPRequestURITooLarge,
                              Net::HTTPMethodNotAllowed]
    end

    def request_json(http_method, path, params, headers)
      response = request(http_method, path, params, headers)
      body = parse_as_json(response.body)
      Response.new(response.code.to_i, body)
    end

    def request(http_method, path, params, headers)
      path = formulate_path(path)
      path = encode_path_params(path, params) if http_method == :get

      headers = @default_headers.merge(headers)
      headers = authenticate(headers)

      request = Net::HTTP::const_get(http_method.to_s.capitalize.to_sym).new(path, headers)
      request.body = params.to_s unless http_method == :get

      basic_auth(request)

      response = http_request(request)

      unless Net::HTTPSuccess === response
        log "endpoint responded with non-success #{response.code} code.\nResponse: #{response.body}"
      end

      response
    end

    def basic_auth(request)
      request.basic_auth(@username, @password) unless @username.empty? && @password.empty?
    end

    def authenticate(headers)
      headers['Authorization'] = "Bearer #{bearer_token}" unless bearer_token.empty?
      headers['Authorization'] = auth_token_header        unless auth_token_header.empty?
      headers
    end

    def http_request(request)
      tries_count ||= @tries
      finished = ->() { (tries_count -= 1).zero? }

      begin
        response = @http.request(request)
      end until !recoverable?(response) || finished.call
      response

    rescue *@errors_to_propagate => error
      log "Request Failed. \nReason: #{error.message}"
      raise

    rescue *@errors_to_recover => error
      warn_on_retry "#{error.message}"
      finished.call ? raise : retry
    end

    def recoverable?(response)
      if @errors_to_recover.any? { |error_class| response.is_a?(error_class) }
        warn_on_retry "#{response.class} response type."
        true
      else
        false
      end
    end

    def parse_as_json(response_body)
      body = response_body
      body = body.nil? || body.empty? ? body : JSON.parse(body)

    rescue JSON::ParserError => error
      log "Parsing response body as JSON failed! Returning raw body. \nDetails: \n#{error.message}"
      body
    end

    def encode_path_params(path, params)
      if params.nil? || params.empty?
        path
      else
        params = stringify_keys(params)
        encoded = URI.encode_www_form(params)
        [path, encoded].join("?")
      end
    end

    def formulate_path(path)
      path = '/'  if path.nil? || path.empty?
      path.strip! if path.respond_to?(:strip)
      path.prepend('/') unless path.chars.first == '/'
      path
    end

    def log(message)
      @logger.error("\n#{LOG_TAG} #{message}.")
    end

    def warn_on_retry(message)
      @logger.warn("\n#{LOG_TAG} #{message} \nRetrying now ..")
    end

    def stringify_keys(params)
      params.respond_to?(:keys) ? params.collect { |k, v| [k.to_s, v] }.to_h : params
    end
  end
end
