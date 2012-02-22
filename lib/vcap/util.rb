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
in your configuration, located in /home/stackato/stackato/etc/vcap.
ERROR
      end
    end
  end
end