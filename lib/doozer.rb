
$:.unshift(File.join(File.dirname(__FILE__), ".."))

require 'rubygems'
require 'eventmachine'
require 'fraggle'
require 'fiber'

# In the event of a lost connection, fraggle will attempt
# other doozers until one accepts or it runs out of options; A NoAddrs
# exception will be raised if that later happens.

module Doozer

  COMPONENT_CONFIG_PATH = "/proc"

  def self.normalize_component_name(c)
    c.gsub(/\_/, '-')
  end

  def self.component_config_path(component_id)
    component_key = normalize_component_name(component_id)
    File.join(COMPONENT_CONFIG_PATH, component_key, "config")
  end

  def self.get_component_config(component_id)
    f = Fiber.current
    EM.next_tick do
      # Fraggle will use $DOOZER_URI when no arguments are passed.
      # pydoozer, and thus kato, will do the same. configuring doozer
      # for your cluster thus involves managing the $DOOZER_URI
      # environment variable.
      Fraggle.connect() do |c, err|
        if err
          raise err.message
        end
        c.rev do |v|
          pat = File.join(component_config_path(component_id), "**")
          req = c.walk(v, pat) do |ents, err|
            config = nil
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
            f.resume config
          end
        end
      end
    end
    config = Fiber.yield
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

  # do the following,
  #  * setup a persistent connection to doozer
  #  * register 'component_id' in doozer ephemeral node
  #  * watch config changes and invoke `callback` if any
  def self.watch_component_config(component_id, config, callback=nil)
    component_id = normalize_component_name(component_id)
    EM.next_tick do
      # we are assuming that this block of code is meant to keep a
      # persistent connection to doozer so that kato can manage the
      # ephemeral nodes.
      Fraggle.connect() do |c, err|
        # name ourself for `kato ls`
        c.rev do |v|
          c.set(v, '/eph', component_id) do |e, err|
            # TODO: what is the best way to handle errors from doozer?
            puts "doozer error: #{err}"
          end
        end
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

  def self.get_component_config_value(component_id, path)
    doozer_path = File.join(component_config_path(component_id), path.map{|p| p.to_s.gsub(/\_/, '-')})

    f = Fiber.current
    EM.next_tick do
      # TODO: re-use watcher connection here
      Fraggle.connect() do |c, err|
        if err
          f.resume(nil, err)
        end
        c.rev do |v|
          c.get(v, doozer_path) do |e, err|
            f.resume(e, err)
          end
        end
      end
    end
    e, err = Fiber.yield

    if err
      raise "Failed to get doozer value " + doozer_path.to_s + " " + err.message
    end
    return JSON.load(e.value)
  end

  def self.set_component_config_value(component_id, path, key, value)
    doozer_path = File.join(component_config_path(component_id), (path + [key]).map{|p| p.to_s.gsub(/\_/, '-')})
    doozer_value = JSON.dump(value)

    f = Fiber.current
    EM.next_tick do
      # TODO: re-use watcher connection here
      Fraggle.connect() do |c, err|
        if err
          f.resume(nil, err)
        end
        c.rev do |v|
          c.set(v, doozer_path, doozer_value) do |e, err|
            f.resume(e, err)
          end
        end
      end
    end
    e, err = Fiber.yield

    if err
      raise "Failed to set doozer value " + doozer_path.to_s + " = " + doozer_value.to_s + " " + err.message
    end
  end
end

