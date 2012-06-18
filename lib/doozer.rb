
$:.unshift(File.join(File.dirname(__FILE__), ".."))

require 'rubygems'
require 'eventmachine'
require 'fraggle'
require 'fraggle/block'
require 'fiber'
require 'json'
require 'yajl'
require 'vcap/logging'

# In the event of a lost connection, fraggle will attempt
# other doozers until one accepts or it runs out of options; A NoAddrs
# exception will be raised if that later happens.

module Fraggle
  module Connection
    def post_init
      VCAP::Logging.logger("doozer").info("Connected to doozer #{addr.to_s}")
      req = Fraggle::Request.new
      req.verb  = Fraggle::Request::Verb::SET
      req.rev   = 9999999999
      req.path  = '/eph'
      req.value = Doozer.client_name
      cb = Proc.new do |e, err|
        if err
          raise "Could not set ephemeral node: " + err.to_s
        end
      end
      send_request(req, cb)
    end
  end
end

module Doozer

  COMPONENT_CONFIG_PATH = "/proc"

  @@client = nil

  def self.logger
    VCAP::Logging.logger("doozer")
  end

  def self.client_name
    return @@client_name
  end

  # setup a persistent connection to doozer
  def self.client(client_name)
    
    @@client_name = client_name
    if not @@client
      f = Fiber.current
      EM.next_tick do
        Fraggle.connect() do |c, err|
          if err
            raise err.message
          end
          f.resume c
        end
      end
      @@client = Fiber.yield
    end
    return @@client
  end

  def self.component_config_path(component_id)
    File.join(COMPONENT_CONFIG_PATH, component_id.to_s, "config")
  end

  def self.get_component_config(component_id, symbolize_keys=false)
    path = File.join(component_config_path(component_id), "**")
    return walk(component_id, path, symbolize_keys=symbolize_keys)
  end

  def self.walk(component_id, path, symbolize_keys=false)
    if EM.reactor_running?
      config, config_rev = self.walk_async(component_id, path, symbolize_keys=symbolize_keys)
    else
      config, config_rev = self.walk_blocking(component_id, path, symbolize_keys=symbolize_keys)
    end
    if config.nil?
      raise "Unable to load config for #{component_id} from doozer"
    end
    return config, config_rev
  end

  def self.walk_async(component_id, path, symbolize_keys=false)
    c = client(component_id)

    f = Fiber.current
    EM.next_tick do
      # Fraggle will use $DOOZER_URI when no arguments are passed.
      # pydoozer, and thus kato, will do the same. configuring doozer
      # for your cluster thus involves managing the $DOOZER_URI
      # environment variable.
      c.rev do |v|
        req = c.walk(v, path) do |ents, err|
          config = nil
          if err
            raise "Fraggle error (" + err.code.to_s + ") " + err.detail.to_s
          else
            ents.each do |e|
              if not config
                config = {}
              end
              _stash_component_config_value(config, e, root_path=path, symbolize_keys=symbolize_keys)
            end
          end
          f.resume config, v
        end
      end
    end
    config, v = Fiber.yield
    return config, v
  end

  def self.walk_blocking(component_id, path, symbolize_keys=false)
    config = nil
    client = Fraggle::Block.connect
    config_rev = client.rev.rev
    walk = client.walk(path)#, rev=config_rev)
    walk.each do |e|
      if not config
        config = {}
      end
      _stash_component_config_value(config, e, root_path=path, symbolize_keys=symbolize_keys)
    end
    return config, config_rev
  end

  def self._is_del(flags)
    flags & 8 == 0 ? false : true
  end

  def self._stash_component_config_value(config, e, root_path, symbolize_keys=false)

    # expects root_path to have trailing slash or trailing "/**"
    # e.g.
    #   /
    #   /**
    #   /proc/<component_id>/config/
    #   /proc/<component_id>/config/**
    #
    stash_depth = root_path.count("/") - 1

    path_parts = e.path.split("/")
    path_parts.shift # remove empty part before first "/"
    (1..stash_depth).each do |i|
      path_parts.shift # remove leading path eg. /proc/<component_id>/config
    end
    config_path = "/" + path_parts.join("/")
    # we won't create a hash for last key
    key = path_parts.pop
    path_parts.each do |part|
      if symbolize_keys
        part = part.to_sym
      end
      if not config.has_key? part
        config[part] = {}
      end
      config = config[part]
    end
    if symbolize_keys
      key = key.to_sym
    end
    if _is_del(e.flags)
      config.delete(key)
    else
      if e.path.start_with? "/ctl/"
        new_value = e.value
      else
        new_value = Yajl::Parser.parse(e.value, :symbolize_keys => symbolize_keys)
      end
      config[key] = new_value
    end
    return config_path, new_value
  end

  # watch config changes and invoke `callback` if any
  def self.watch_component_config(component_id, config, rev=nil, callback=nil, symbolize_keys=false)

    c = client(component_id)

    EM.next_tick do
      c.rev do |v|
        if not rev
          rev = v
        end
        path = File.join(component_config_path(component_id), "**")
        watch(component_id, path, config, rev, callback=callback, symbolize_keys=symbolize_keys)
      end
    end
  end

  # watch changes within doozer and invoke `callback` if any
  def self.watch(component_id, path, config, rev, callback=nil, symbolize_keys=false)

    logger.info("Watching doozer config from rev=#{rev.to_s}")

    c = client(component_id)

    EM.next_tick do
      c.watch(rev, path) do |e, err|
        if err
          raise "Doozer watch failed for " + path.to_s + " " + err.message
        end
        config_path, value = _stash_component_config_value(config, e, root_path=path, symbolize_keys=symbolize_keys)
        is_del = _is_del(e.flags)
        if callback
          callback.call(config_path, value, e.rev, is_del)
        end
      end
    end
  end

  def self.get_component_config_value(component_id, path, symbolize_keys=false)
    doozer_path = component_config_path(component_id) + path
    if EM.reactor_running?
      return _get_component_config_value_async(component_id, doozer_path, symbolize_keys)
    else
      return _get_component_config_value_blocking(component_id, doozer_path, symbolize_keys)
    end
  end

  def self._get_component_config_value_blocking(component_id, doozer_path, symbolize_keys=false)
    client = Fraggle::Block.connect
    e = client.get(doozer_path)
    e.value
  end

  def self._get_component_config_value_async(component_id, doozer_path, symbolize_keys=false)

    c = client(component_id)

    f = Fiber.current
    EM.next_tick do
      c.rev do |v|
        c.get(v, doozer_path) do |e, err|
          f.resume(e, err)
        end
      end
    end
    e, err = Fiber.yield

    if err
      raise "Failed to get doozer value " + doozer_path.to_s + " " + err.message
    end
    return Yajl::Parser.parse(e.value, :symbolize_keys => symbolize_keys)
  end

  def self.set_component_config_value(component_id, path, value, rev=9999999999)
    doozer_path = component_config_path(component_id) + path
    set_config_value(component_id, doozer_path, value, rev)
  end

  def self.set_config_value(component_id, path, value, rev=9999999999)
    if EM.reactor_running?
      self._set_config_value_async(component_id, path, value, rev)
    else
      self._set_config_value_blocking(component_id, path, value, rev)
    end
  end

  def self._set_config_value_async(component_id, doozer_path, value, rev)
    unless rev
      raise "rev expected"
    end
    doozer_value = JSON.dump(value)

    c = client(component_id)

    f = Fiber.current
    EM.next_tick do
      c.set(rev, doozer_path, doozer_value) do |e, err|
        f.resume(e, err)
      end
    end
    e, err = Fiber.yield

    if err
      raise "Failed to set doozer value #{doozer_path.to_s} (r#{rev.to_s}) = #{doozer_value.to_s} : " + err.message
    end
    
    e.rev
  end

  def self._set_config_value_blocking(component_id, doozer_path, value, rev)
    unless rev
      raise "rev expected"
    end
    doozer_value = JSON.dump(value)
    client = Fraggle::Block.connect
    e = client.set(doozer_path, doozer_value, rev)
    e.rev
  end

  def self.del_component_config_value(component_id, path, value, rev=9999999999)
    doozer_path = component_config_path(component_id) + path
    del_config_value(component_id, doozer_path, value, rev)
  end

  def self.del_config_value(component_id, path, rev=9999999999)
    if EM.reactor_running?
      self._del_config_value_async(component_id, path, rev)
    else
      self._del_config_value_blocking(component_id, path, rev)
    end
  end

  def self._del_config_value_async(component_id, doozer_path, rev)
    unless rev
      raise "rev expected"
    end

    c = client(component_id)

    f = Fiber.current
    EM.next_tick do
      c.del(rev, doozer_path) do |e, err|
        f.resume(e, err)
      end
    end
    e, err = Fiber.yield

    if err
      raise "Failed to del doozer path " + doozer_path.to_s + " " + err.message
    end
    
    e.rev
  end

  def self._del_config_value_blocking(component_id, doozer_path, rev)
    unless rev
      raise "rev expected"
    end
    client = Fraggle::Block.connect
    e = client.del(doozer_path, rev)
    e.rev
  end

  def self.fake_config_file_load(file_path)
    # Take the full yml file path and extra the component_id
    # for use with doozer config
    component_id = file_path.sub(/^.*\/([^\/\.]+)\.yml$/, '\1')
    get_component_config(component_id)
  end


end

