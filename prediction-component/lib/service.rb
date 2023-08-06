require_relative 'component'

component_name = 'league-service'
ComponentHost.start(component_name) do |host|
  host.register(Component)
end