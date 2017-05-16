require 'net/http'
require 'json'
require 'securerandom'
require 'erb'
require 'logger'


module NetworkClient
  # This class is simple HTTP client that meant to be initialized configured with a single URI.
  # Subsequent calls should target endpoints/paths of that URI.
  #
  # Return values of its rest-like methods is Struct holding two values for the code and response
  # body parsed as JSON.
  #
  class Client

    HTTP_VERBS = {
      :get    => Net::HTTP::Get,
      :post   => Net::HTTP::Post,
      :put    => Net::HTTP::Put,
      :delete => Net::HTTP::Delete
    }

    def initialize(endpoint:, tries: 1, headers: {})
      @uri = URI.parse(endpoint)
      @tries = tries

      set_http_client
      set_default_headers(headers)
      set_logger
      set_response_struct
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

    def set_logger
      @logger = if defined?(Rails)
        Rails.logger
      elsif block_given?
        yield
      else
        logger = Logger.new(STDOUT)
        logger.level = Logger::DEBUG
        logger
      end
    end

    private

    def set_http_client
      @http = Net::HTTP.new(@uri.host, @uri.port)
      @http.use_ssl = @uri.scheme == 'https' ? true : false
      @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    def set_default_headers(headers)
      defaults = { 'accept' => 'application/json', 'Content-Type' => 'application/json' }
      @default_headers = defaults.merge(headers)
    end

    def set_response_struct
      @response_struct = Struct.new(:code, :body)
    end

    def request_json(http_method, path, params, headers)
      response = request(http_method, path, params, headers)
      body = JSON.parse(response.body)

      @response_struct.new(response.code, body)

    rescue JSON::ParserError => error
      @logger.error "parsing response body as json failed.\n Details: \n #{error.message}"
      response
    end

    def request(http_method, path, params, headers)
      headers = @default_headers.merge(headers)

      case http_method
      when :get
        full_path = encode_path_params(path, params)
        request = HTTP_VERBS[http_method].new(full_path, headers)
      else
        request = HTTP_VERBS[http_method].new(path, headers)
        request.set_form_data(params)
      end

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
      rescue errors_to_recover_by_retry => error
        @logger.warn(error.message)
        (tries_count -= 1).zero? ? raise : retry
      else
        response
      end
    end

    def errors_to_recover_by_retry
      [Errno::ECONNREFUSED, Net::HTTPServiceUnavailable, Net::ProtocolError, Net::ReadTimeout,
       Net::OpenTimeout, OpenSSL::SSL::SSLError]
    end

    def errors_to_recover_by_propogate
    end

    def encode_path_params(path, params)
      return path if params.empty?
      encoded = URI.encode_www_form(params)
      [path, encoded].join("?")
    end
  end
end
