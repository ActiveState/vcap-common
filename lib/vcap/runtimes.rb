require 'yaml'

RUNTIMES_LIST = File.join( ENV['HOME'], 'stackato/etc/runtimes.yml' )

module VCAP
      class Runtimes
        def self.list_for_cc
          res = {}
          symbolize_keys(_get["runtimes"]).each do |k,v|
          res[k] = { :version => v[:version] }
          res[k][:debug_modes] = v[:debug_modes] if v[:debug_modes]
        end

        res
      end

      def self.list
        _get["runtimes"]
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

      def self._get
        YAML.load_file(RUNTIMES_LIST)
      end
    end
end