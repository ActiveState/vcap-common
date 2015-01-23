# XXX: adapt for v2

module Stackato
  class Logyard
    @@logyard_uid = nil

    def self.dea_startup_hook
      # XXX: this shouldn't be mandatory, but unfortunately dea's uuid is not
      # stored locally for logyard to retrieve from. so we go the other way
      # around (storing logyard's uuid locally) just like fence does.
      logger.info("Waiting for logyard...")
      loop do
        @@logyard_uid = File.open('/tmp/logyard.uid', 'r') { |f| f.read.strip } rescue nil
        break if @@logyard_uid
      end
      @apptail_nats_msg_prefix = "logyard.#{@@logyard_uid}"
      logger.info("logyard #{@@logyard_uid} detected")
    end

    def self.apptail_nats_msg_prefix
      @apptail_nats_msg_prefix
    end

    def self.register_docker_logs_with_logyard(options = {})
      logger.info("Registering instance with logyard: #{options[:logfiles]}")

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
      logger.info("Done registering with logyard.")  
    end

    # 
    def self.make_instance_identifier(user, app, instance_index)
      return {
        :user => user,
        :app => app,
        :instance_index => instance_index
      }
    end

    def self.report_event(event_name, message, instance_identifier)
      # sanity check
      unless instance_identifier.is_a?(Hash)
        raise "instance_identifier must be a Hash; not #{instance_identifier}"
      end
      [:user, :app, :instance_index].each do |key|
        unless instance_identifier.has_key? key
          raise "instance_identifier is missing key #{key}"
        end
      end
        
      event = instance_identifier.dup
      event[:event] = event_name
      event[:message] = message
      Steno.logger("common.logyard").info("TIMELINE #{event.to_json}")
    end
    
  end
end
