
require 'rubygems'
require 'eventmachine'
require 'fraggle'

# In the event of a lost connection, fraggle will attempt
# other doozers until one accepts or it runs out of options; A NoAddrs
# exception will be raised if that later happens.

module Doozer

  COMPONENT_CONFIG_PATH = "/proc"

  DEFAULT_URI = "doozer:?" + [
    "ca=127.0.0.1:8046"
  ].join("&")

  def self.get_config(component_id)
    config = nil
    config_path = File.join(COMPONENT_CONFIG_PATH, component_id)
    EM.run do
      Fraggle.connect(DEFAULT_URI) do |c, err|
        if err
          raise err.message
        end
        c.rev do |v|
          req = c.walk(v, config_path) do |ents, err|
            if err
              raise "Fraggle error (" + err.code.to_s + ") " + err.detail.to_s
            else
              ents.each do |e|
                if not config
                  config = Hash.new
                end
                path = config
                path_parts = e.path.split("/")
                # remove empty part before first "/"
                path_parts.shift
                # replace dashes with underscores in keys
                path_parts = path_parts.map{|key| key.gsub(/\-/, '_')}
                # we won't create a hash for last key
                last_key = path_parts.pop
                path_parts.each do |part|
                  path[part] = Hash.new
                  path = path[part]
                end
                path[last_key] = e.value
              end
            end
            EM.stop_event_loop
          end
        end
      end
    end
    return config
  end
end

