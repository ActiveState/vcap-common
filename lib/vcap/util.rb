require 'socket'
require 'uri'
require 'timeout'

module VCAP
  module Util
    def self.validate_nats(uri)
      uri = URI.parse(uri)
      begin
        timeout(5) do
          natssock = TCPSocket.new uri.host, uri.port
        end
      rescue
        abort <<ERROR

Stackato is unable to start!

Unable to connect to NATS. You may have specified an invalid mbus setting 
in your configuration (check "kato config <component name> mbus").
ERROR
      end
    end

    def self.symbolize_keys(data)
      case data
      when Array
        data.map { |arg| symbolize_keys(arg) }
      when Hash
        Hash[
          data.map { |key, value|  
            k = key.is_a?(String) ? key.to_sym : key
            v = symbolize_keys(value)
            [k,v]
          }]
      else
        data
      end
    end
  end
end