
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
    path_parts = e.path.split("/")
    path_parts.shift # remove empty part before first "/"
    path_parts.shift # remove "proc"
    path_parts.shift # remove component_id
    path_parts.shift # remove "config"
    # replace dashes with underscores in keys and make symbols
    path_parts = path_parts.map{|key| key.gsub(/\-/, '_').to_sym}
    # we won't create a hash for last key
    key = path_parts.pop
    path_parts.each do |part|
      part_sym = part.to_sym
      if not config.has_key? part_sym
        config[part_sym] = {}
      end
      config = config[part_sym]
    end
    new_value = JSON.load(e.value)
    config[key] = new_value
    return path_parts, key, new_value
  end

  def self.watch_component_config(component_id, config, callback=nil)
    EM.next_tick do
      Fraggle.connect(DEFAULT_URI) do |c, err|
        if err
          raise err.message
        end
        c.rev do |v|
          c.watch(v, File.join(component_config_path(component_id), "**")) do |e, err|
            path, key, value = _stash_component_config_value(config, e)
            if callback
              callback.call(path, key, value)
            end
          end
        end
      end
    end
  end

  def self.set_component_config_value(component_id, path, key, value)
    EM.next_tick do
      Fraggle.connect(DEFAULT_URI) do |c, err|
        if err
          raise err.message
        end
        c.rev do |v|
          doozer_path = File.join(component_config_path(component_id), (path + [key]).map{|p| p.to_s.gsub(/\_/, '-')})
          doozer_value = JSON.dump(value)
          c.set(v, doozer_path, doozer_value) do |e, err|
            if err
              raise "Failed to set doozer value " + doozer_path.to_s + " = " + doozer_value.to_s + " " + err.message
            end
          end
        end
      end
    end
  end

end

