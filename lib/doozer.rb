
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

  def self.component_config_path(component_id)
    component_key = component_id.gsub(/\_/, '-')
    File.join(COMPONENT_CONFIG_PATH, component_key, "config")
  end

  def self.get_component_config(component_id)
    config = nil
    EM.run do
      Fraggle.connect(DEFAULT_URI) do |c, err|
        if err
          raise err.message
        end
        c.rev do |v|
          req = c.walk(v, File.join(component_config_path(component_id), "**")) do |ents, err|
            if err
              raise "Fraggle error (" + err.code.to_s + ") " + err.detail.to_s
            else
              ents.each do |e|
                if not config
                  config = {}
                end
                _stash_component_config_value(config, e)
              end
            end
            EM.stop_event_loop
          end
        end
      end
    end
    return config
  end

  def self._stash_component_config_value(config, e)
    path = config
    path_parts = e.path.split("/")
    path_parts.shift # remove empty part before first "/"
    path_parts.shift # remove "proc"
    path_parts.shift # remove component_id
    path_parts.shift # remove "config"
    # replace dashes with underscores in keys
    path_parts = path_parts.map{|key| key.gsub(/\-/, '_')}
    # we won't create a hash for last key
    last_key = path_parts.pop
    path_parts.each do |part|
      part_sym = part.to_sym
      if not path.has_key? part_sym
        path[part_sym] = {}
      end
      path = path[part_sym]
    end
    path[last_key.to_sym] = JSON.load(e.value)
    return path_parts + [last_key]
  end

  def self.watch_component_config(component_id, config, callback=nil)
    EM.next_tick do
      Fraggle.connect(DEFAULT_URI) do |c, err|
        if err
          raise err.message
        end
        c.rev do |v|
          c.watch(v, File.join(component_config_path(component_id), "**")) do |e, err|
            path_parts = _stash_component_config_value(config, e)
            if callback
              callback.call(e.path, path_parts, e.value)
            end
          end
        end
      end
    end
  end

end

