require_relative 'component'

component_name = 'team-strength-service'
ComponentHost.start(component_name) do |host|
  host.register(Component)
end