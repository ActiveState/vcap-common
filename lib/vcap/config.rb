# Copyright (c) 2009-2011 VMware, Inc.
require 'yaml'

require 'vcap/common'
require 'membrane'

module VCAP
  class Config
    class << self
      attr_reader :schema

      def define_schema(&blk)
        @schema = Membrane::SchemaParser.parse(&blk)
      end

      def from_file(filename, symbolize_keys=true)
        config = YAML.load_file(filename)
        config = VCAP.symbolize_keys(config) if symbolize_keys
        @schema.validate(config)
        config
      end

      def from_doozer(component_id, symbolize_keys=true)
        $LOAD_PATH << File.join(ENV['HOME'], 'stackato/kato/lib')
        require 'kato/doozer'
        config, config_rev = Kato::Doozer.get_component_config(component_id)
        @schema.validate(config)
        config = VCAP.symbolize_keys(config) if symbolize_keys
        [config, config_rev]
      end

      def to_file(config, out_filename)
        @schema.validate(config)
        File.open(out_filename, 'w+') do |f|
          YAML.dump(config, f)
        end
      end
    end
  end
end
