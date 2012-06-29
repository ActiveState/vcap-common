require 'vcap/util'

module VCAP
  module ServicesEnv

    # Call `blk` for the only item in the array; else, do nothing
    def self.only_item(arr, &blk)
      return unless arr and arr.size == 1
      blk.call(arr[0])
    end

    def self.create_services_env(services)
      e = {}
      return e unless services

      # Create $STACKATO_SERVICES and $VCAP_SERVICES

      stackato_services = {}
      vcap_services = {}

      whitelist = [:name, :label, :plan, :tags, :plan_option, :credentials]

      # services is already symbolized in staging, but not in dea
      VCAP::Util.symbolize_keys(services).each do |s|
        stackato_services[s[:name]] = stackato_hash = {}

        vcap_hash = {}
        vcap_services[s[:label]] ||= []
        vcap_services[s[:label]] << vcap_hash

        whitelist.each {|k| vcap_hash[k] = s[k] if s[k]}
        if s[:label].start_with? 'filesystem'
          stackato_hash[:dir] = vcap_hash[:dir] = "/app/fs/#{s[:name]}"
          vcap_hash.delete(:credentials)
        elsif s[:credentials].is_a? Hash
          s[:credentials].each {|k,v| stackato_hash[k] = v}
        end
      end

      e['VCAP_SERVICES'] = vcap_services.to_json
      e['STACKATO_SERVICES'] = stackato_services.to_json

      # Add individual environment variables for each service type as long
      # as only a single service of that type has been bound.

      only_item(vcap_services['mysql-5.5']) do |s|
        c = s[:credentials]
        e["MYSQL_URL"] = "mysql://#{c[:user]}:#{c[:password]}@#{c[:host]}:#{c[:port]}/#{c[:name]}"
      end

      only_item(vcap_services['postgresql-9.1']) do |s|
        c = s[:credentials]
        e["POSTGRESQL_URL"] = "postgres://#{c[:user]}:#{c[:password]}@#{c[:host]}:#{c[:port]}/#{c[:name]}"
      end

      # Store relational database url also in $DATABASE_URL if there is just one database
      if ((vcap_services['mysql-5.5'] || []) + (vcap_services['postgresql-9.1'] || [])).size == 1
        e["DATABASE_URL"] = e["MYSQL_URL"] || e["POSTGRESQL_URL"]
      end

      only_item(vcap_services['mongodb-1.8']) do |s|
        c = s[:credentials]
        e["MONGODB_URL"] = "mongodb://#{c[:username]}:#{c[:password]}@#{c[:host]}:#{c[:port]}/#{c[:db]}"
      end

      only_item(vcap_services['redis-2.2']) do |s|
        c = s[:credentials]
        # redis does not seem to require a 'user' field
        e["REDIS_URL"] = "redis://user:#{c[:password]}@#{c[:host]}:#{c[:port]}/"
      end

      only_item(vcap_services['rabbitmq-2.4']) do |s|
        c = s[:credentials]
        e["RABBITMQ_URL"] = "amqp://#{c[:username]}:#{c[:password]}@#{c[:host]}:#{c[:port]}/#{c[:vhost]}"
      end

      only_item(vcap_services['memcached-1.4']) do |s|
        c = s[:credentials]
        e["MEMCACHE_URL"] = "#{c[:host]}:#{c[:port]}"
      end

      only_item(vcap_services['filesystem-1.0']) do |s|
        e["STACKATO_FILESYSTEM"] = s[:dir]
      end

      # For filesystem services we will also create a specific variable for each one
      (vcap_services['filesystem-1.0'] || []).each do |s|
        e["STACKATO_FILESYSTEM_#{s[:name].upcase.gsub('-', '_')}"] = s[:dir]
      end

      return e
    end

  end
end
