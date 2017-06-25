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
    LOG_TAG = "[NET CLIENT]:"

    attr_reader :username, :password, :default_headers, :logger

    # error list for retrying strategy. Takes priority over *:errors_to_propogate*.
    # Initially contains common errors encountered usually in net calls.
    attr_accessor :errors_to_recover

    # error list for stop and propagate strategy. Contains only StandardError by default.
    attr_accessor :errors_to_propagate
    StandardError

    # Construct and prepare client for requests targeting :endpoint.
    #
    # *endpoint*:
    #   Uri for the host with schema and port. any other segment like paths will be discarded.
    # *tries*:
    #   Number to specify how many is to repeat failed calls.
    # *headers*:
    #   Hash to contain any common HTTP headers to be set in client calls.
    # *username*:
    #  for HTTP basic authentication. Applies on all requests.
    # *password*:
    #  for HTTP basic authentication. Applies on all requests.
    #
    # ==== Example:
    # =>
    #
    def initialize(endpoint:, tries: 1, headers: {}, username: nil, password: nil)
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

    def request_json(http_method, path, params, headers)
      response = request(http_method, path, params, headers)
      body = JSON.parse(response.body)

      Response.new(response.code, body)

    rescue JSON::ParserError => error
      @logger.error "#{LOG_TAG}: Parsing response body as JSON failed.\nDetails: \n#{error.message}"
      response
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
      case response
      when Net::HTTPSuccess
        true
      else
        @logger.error "endpoint responded with a non-success #{response.code} code."
      end

      response
    end

    def http_request(request)
      begin
        tries_count ||= @tries
        response = @http.request(request)
      rescue *@errors_to_recover => error
        @logger.warn "[Error]: #{error.message} \nRetry .."
        (tries_count -= 1).zero? ? raise : retry
      rescue *@errors_to_propogate
        raise
      ensure
        response
      end
    end

    def basic_auth(request)
      unless @username.empty? && @password.empty?
        request.basic_auth(@username, @password)
      end
    end

    def define_error_strategies
      @errors_to_recover   = [Errno::ECONNREFUSED, Net::HTTPServiceUnavailable, Net::ProtocolError,
                              Net::ReadTimeout, Net::OpenTimeout, OpenSSL::SSL::SSLError,
                              SocketError]
      @errors_to_propogate = [StandardError]
    end

    def encode_path_params(path, params)
      if params.empty?
        path
      else
        encoded = URI.encode_www_form(params)
        [path, encoded].join("?")
      end
    end

    def formulate_path(path)
      path.chars.last.nil? ? "#{path}/" : path
    end

  end
end
