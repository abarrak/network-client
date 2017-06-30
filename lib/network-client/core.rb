require 'net/http'
require 'json'
require 'logger'

module NetworkClient
  class Client

    HTTP_VERBS = {
      :get    => Net::HTTP::Get,
      :post   => Net::HTTP::Post,
      :put    => Net::HTTP::Put,
      :delete => Net::HTTP::Delete
    }

    DEFAULT_HEADERS = { 'accept' => 'application/json',
                        'Content-Type' => 'application/json' }.freeze

    # The success response template. Represents the return of rest-like methods holding two values:
    # HTTP response code, and body (parsed as json if request type is json).
    Response = Struct.new(:code, :body)

    # Stamp in front of each log written by client *@logger*
    LOG_TAG = '[NETWORK CLIENT]:'.freeze

    attr_reader :username, :password, :default_headers, :logger, :tries

    # Error list for retrying strategy.
    # Initially contains common errors encountered usually in net calls.
    attr_accessor :errors_to_recover

    # Error list for stop and propagate strategy.
    # Takes priority over *:errors_to_recover*.
    # Do not assign ancestor error classes here that prevent retry for descendant ones.
    attr_accessor :errors_to_propagate

    ##
    # Construct and prepare client for requests targeting :endpoint.
    #
    # === Parameters:
    #
    # *endpoint*:
    # Uri for the host with schema and port. any other segment like paths will be discarded.
    # *tries*:
    # Number to specify how many is to repeat failed calls. Default is 2.
    # *headers*:
    # Hash to contain any common HTTP headers to be set in client calls.
    # *username*:
    # for HTTP basic authentication. Applies on all requests. Default to nil.
    # *password*:
    # for HTTP basic authentication. Applies on all requests. Default to nil.
    #
    # === Example:
    #   require "network-client"
    #
    #   github_client = NetworkClient::Client.new(endpoint: 'https://api.github.com')
    #   github_client.get '/emojis'
    #   #=> { "+1": "https://assets-cdn.github.com/images/icons/emoji/unicode/1f44d.png?v7",
    #        "-1": "https://assets-cdn.github.com/images/icons/emoji/unicode/1f44e.png?v7",
    #        "100": "https://assets-cdn.github.com/images/icons/emoji/unicode/1f4af.png?v7",
    #        ... }
    #
    def initialize(endpoint:, tries: 2, headers: {}, username: nil, password: nil)
      @uri = URI.parse(endpoint)
      @tries = tries

      set_http_client
      set_default_headers(headers)
      set_basic_auth(username, password)
      set_logger
      define_error_strategies
    end

    def get(path, params = {}, headers = {})
      request_json :get, path, params, headers
    end

    def post(path, params = {}, headers = {})
      request_json :post, path, params, headers
    end

    def put(path, params = {}, headers = {})
      request_json :put, path, params, headers
    end

    def delete(path, params = {}, headers = {})
      request_json :delete, path, params, headers
    end

    def post_form(path, params = {}, headers = {})
      raise NotImplementedError
    end

    def put_form(path, params = {}, headers = {})
      raise NotImplementedError
    end

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
      headers = @default_headers.merge(headers)
      path = formulate_path(path)

      case http_method
      when :get
        full_path = encode_path_params(path, params)
        request = HTTP_VERBS[http_method].new(full_path, headers)
      else
        request = HTTP_VERBS[http_method].new(path, headers)
        request.body = params.to_s
      end

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
        encoded = URI.encode_www_form(params)
        [path, encoded].join("?")
      end
    end

    def formulate_path(path)
      path = '/' if path.nil? || path.empty?
      path.prepend('/') unless path.chars.first == '/'
      path
    end

    def log(message)
      @logger.error("\n#{LOG_TAG} #{message}.")
    end

    def warn_on_retry(message)
      @logger.warn("\n#{LOG_TAG} #{message} \nRetrying now ..")
    end
  end
end
