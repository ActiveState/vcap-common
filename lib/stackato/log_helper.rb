
module Stackato
  class LogHelper

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
      Steno.logger("common.log").info("TIMELINE #{event.to_json}")
    end
    
  end
end
