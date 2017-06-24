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

    Response = Struct.new(:code, :body)

    def initialize(endpoint:, tries: 1, headers: {}, username: nil, password: nil)
      @uri = URI.parse(endpoint)
      @tries = tries

      set_http_client
      set_default_headers(headers)
      set_basic_auth(username, password)
      set_logger
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
      @logger.error "parsing response body as json failed.\n Details: \n #{error.message}"
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
      rescue *errors_to_recover_by_retry => error
        @logger.warn "[Error]: #{error.message} \nRetry .."
        (tries_count -= 1).zero? ? raise : retry
      else
        response
      end
    end

    def basic_auth(request)
      unless @username.empty? && @password.empty?
        request.basic_auth(@username, @password)
      end
    end

    def errors_to_recover_by_retry
      [Errno::ECONNREFUSED, Net::HTTPServiceUnavailable, Net::ProtocolError, Net::ReadTimeout,
       Net::OpenTimeout, OpenSSL::SSL::SSLError, SocketError]
    end

    def errors_to_recover_by_propogate
      # TODO: make configurable set of errors that stop net call without retry.
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
