
require 'eventide/postgres'
require 'consumer/postgres'
require 'component_host'

require "saulabs/trueskill"

class RecordGameCreation
  include Messaging::Message

  attribute :game_id, Numeric
  attribute :first_team_id, Numeric
  attribute :second_team_id, Numeric
  attribute :winning_team, Numeric
  attribute :time, String
end

class GameCreationRecorded
  include Messaging::Message

  attribute :game_id, Numeric
  attribute :first_team_id, Numeric
  attribute :second_team_id, Numeric
  attribute :winning_team, Numeric
  attribute :time, String

  attribute :recorded_for_team_id, Numeric
  attribute :processed_time, String
end


class TeamStrength
  include Schema::DataStructure

  attribute :team_id, Numeric
  attribute :mean, Numeric, default: 1500
  attribute :deviation, Numeric, default: 1000

  def update_to(mean, deviation)
    self.mean = mean
    self.deviation = deviation
  end
end

class TeamStrength
  module Transform
    # When reading: Convert hash to TeamStrength
    def self.instance(raw_data)
      TeamStrength.build(raw_data)
    end

    # When writing: Convert TeamStrength to hash
    def self.raw_data(instance)
      instance.to_h
    end
  end
end

class Projection
  include EntityProjection

  entity_name :team_strength

  apply GameCreationRecorded do |event|
    team_strength.team_id = event.recorded_for_team_id

    if event.recorded_for_team_id == event.first_team_id
      if event.winning_team == 1 
        team_strength.update_to(team_strength.mean + 1, team_strength.deviation - 1)
      else
        team_strength.update_to(team_strength.mean - 1, team_strength.deviation - 1)
      end
    else
      if event.winning_team == 2
        team_strength.update_to(team_strength.mean + 1, team_strength.deviation - 1)
      else
        team_strength.update_to(team_strength.mean - 1, team_strength.deviation - 1)
      end
    end
  end
end

class Store
  include EntityStore

  category :team_strength
  entity TeamStrength
  projection Projection
  reader MessageStore::Postgres::Read
  snapshot EntitySnapshot::Postgres, interval: 5
end

class Handler
  include Messaging::Handle
  include Messaging::StreamName

  dependency :write, Messaging::Postgres::Write
  dependency :clock, Clock::UTC
  dependency :store, Store

  def configure
    Messaging::Postgres::Write.configure(self)
    Clock::UTC.configure(self)
    Store.configure(self)
  end

  category :team_strength

  handle RecordGameCreation do |command|
    result_event = GameCreationRecorded.follow(command)
    result_event.processed_time = clock.iso8601

    result_event.recorded_for_team_id = command.first_team_id
    write.(result_event, stream_name(command.first_team_id))

    result_event.recorded_for_team_id = command.second_team_id
    write.(result_event, stream_name(command.second_team_id))
  end
end

class TeamStrengthConsumer
  include Consumer::Postgres

  handler Handler
end

module Component
  def self.call
    team_strength_command_stream_name = 'team_strength:command'
    TeamStrengthConsumer.start(team_strength_command_stream_name)
  end
end
