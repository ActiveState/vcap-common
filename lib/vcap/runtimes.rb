require 'yaml'

RUNTIMES_LIST = File.join( ENV['HOME'], 'stackato/etc/runtimes.yml' )

module VCAP
	class Runtimes
		def self.list_for_cc
      res = {}
		  _get[:runtimes].each do |k,v|
        res[k] = { :version => v[:version] }
        res[k][:debug_modes] = v[:debug_modes] if v[:debug_modes]
      end

      res
		end

    def self.list
      _get[:runtimes]
    end

		private

		def _get
		  YAML.load_file(RUNTIMES_LIST)
		end
	end
end