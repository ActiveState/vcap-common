spec = Gem::Specification.new do |s|
  s.name = 'vcap_common'
  s.version = '1.0.12'
  s.date = '2011-02-09'
  s.summary = 'vcap common'
  s.homepage = "http://github.com/vmware-ac/core"
  s.description = 'common vcap classes/methods'

  s.authors = ["Derek Collison"]
  s.email = ["derek.collison@gmail.com"]

  s.add_dependency('eventmachine', '~> 1.0.0')
  s.add_dependency('thin', '>= 1.4.0', '< 1.6')
  s.add_dependency('yajl-ruby', '~> 1.1.0')
  s.add_dependency('nats', '~> 0.4.26')
  s.add_dependency('posix-spawn', '~> 0.3.6')
  s.add_dependency('stackato-kato', '~> 2.8.0')
  s.add_development_dependency('rake', '~> 0.9.2')

  s.require_paths = ['lib']

  s.files = Dir["lib/**/*.rb"]
end
