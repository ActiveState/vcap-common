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
      logger.info("logyard #{@@logyard_uid} detected")
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
      }
      key = "logyard.#{@@logyard_uid}.newinstance"
      logger.info("Publishing to #{key}: #{msg}")
      options[:nats].publish(key, msg)
      logger.info("Done registering with logyard.")  
    end

    def self.report_event(event, message, instance_index, user, app)
      name = app[:name]
      event = {
        :user => user,
        :app => app,
        :event => event,
        :instance_index => instance_index,
        :message => message,
      }
      Steno.logger("cc.logyard").info("TIMELINE #{event.to_json}")
    end
    
  end
end
