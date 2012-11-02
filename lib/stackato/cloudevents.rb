# require'ing this file will add a EVENT level to VCAP::Logging
# It is essential to require this file before any call to VCAP::Logging.setup_from_config

require 'vcap/logging'
require 'vcap/logging/logger'

# HACK: vcap-logging lacks an API to *add* a logging level, so we are
# relying on its internal assumption that calling `reset` again is OK,
# https://github.com/cloudfoundry/common/blob/master/vcap_logging/lib/vcap/logging.rb#L43
info_sort_order = VCAP::Logging::LOG_LEVELS[:info]
VCAP::Logging::LOG_LEVELS[:event] = info_sort_order - 1
VCAP::Logging.reset
