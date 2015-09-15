module Stackato
  class ApptailRegistrar
    
    def self.get_apptail_uid
      # XXX: this shouldn't be mandatory, but unfortunately dea's uuid is not
      # stored locally for apptail to retrieve from. so we go the other way
      # around (storing apptail's uuid locally) just like fence does.
      uid = File.open('/tmp/apptail.uid', 'r') { |f| f.read.strip } rescue nil
      return uid if uid
      logger.info("Waiting for apptail...")
      backoff = ExponentialBackoff.new
      while !uid
        logger.debug("Waiting #{backoff.wait_time} msec for apptail...")
        backoff.sleep
        uid = File.open('/tmp/apptail.uid', 'r') { |f| f.read.strip } rescue nil
      end
      uid
    end

    def self.dea_startup_hook
      apptail_uid = get_apptail_uid
      @apptail_nats_msg_prefix = "apptail.#{apptail_uid}"
      logger.info("apptail #{apptail_uid} detected")
    end

    def self.apptail_nats_msg_prefix
      @apptail_nats_msg_prefix
    end

    def self.register_docker_logs_with_apptail(options = {})
      logger.info("Registering instance with apptail: #{options[:logfiles]}")

      raise "rootfs is nil" if options[:rootfs].nil?
      raise "type is nil" if options[:type].nil?

      msg = {
       :appguid => options[:appguid],
       :appname => options[:appname],
       :appspace => options[:appspace],
       :type => options[:type],
       :index => options[:index],
       :docker_id => options[:docker_id],
       :rootpath => options[:rootfs],
       :logfiles => options[:logfiles],
       :docker_streams => options[:docker_streams],
      }
      key = "#{apptail_nats_msg_prefix}.newinstance"
      logger.info("Publishing to #{key}: #{msg}")
      options[:nats].publish(key, msg)
      logger.info("Done registering with apptail.")  
    end
  end

  class ExponentialBackoff
    Max_c = 17 # EB(17) = 65535.5 msec ~= 1 minute
    def initialize
      @c = 1 # interpret as msec
    end

    def sleep
      sleep(wait_time)
      @c += 1 if @c < Max_c
    end

    def wait_time
      ((2 ** @c)/2 - 0.5) / 1000.0
    end
  end

end

