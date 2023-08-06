
require 'eventide/postgres'
require 'consumer/postgres'
require 'try'

require "saulabs/trueskill"

require 'component_host'


class RecordGameCreation
  include Messaging::Message

  attribute :league_id, Numeric

  attribute :game_id, Numeric
  attribute :first_team_id, Numeric
  attribute :second_team_id, Numeric
  attribute :winning_team, Numeric
  attribute :time, String
end

class GameCreationRecorded
  include Messaging::Message

  attribute :league_id, Numeric

  attribute :game_id, Numeric
  attribute :first_team_id, Numeric
  attribute :second_team_id, Numeric
  attribute :winning_team, Numeric
  attribute :time, String

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

class League
  include Schema::DataStructure

  attribute :league_id, Numeric
  attribute :teams

  def initialize
    self.teams = {}
  end

  def []=(team_id, team_strength)
    self.teams[team_id] = team_strength
  end

  def [](team_id)
    self.teams[team_id] || TeamStrength.new
  end
end

class League
  module Transform
    # When reading: Convert hash to League
    def self.instance(raw_data)
      League.build(raw_data)
    end

    # When writing: Convert League to hash
    def self.raw_data(instance)
      instance.to_h
    end
  end
end

class Projection
  include EntityProjection

  entity_name :league

  apply GameCreationRecorded do |event|

    league.league_id = event.league_id

    first_team = league[event.first_team_id]
    second_team = league[event.second_team_id]

    team1 = [::Saulabs::TrueSkill::Rating.new(first_team.mean, first_team.deviation, 1.0)]
    team2 = [::Saulabs::TrueSkill::Rating.new(second_team.mean, second_team.deviation, 1.0)]

    result = event.winning_team == 1 ? [team1, team2] : [team2, team1]
    graph = ::Saulabs::TrueSkill::FactorGraph.new(result, [1,2])
    graph.update_skills

    ts = TeamStrength.new
    ts.team_id = event.first_team_id
    ts.mean = team1.first.mean
    ts.deviation = team1.first.deviation
    league[event.first_team_id] = ts
    
    ts = TeamStrength.new
    ts.team_id = event.second_team_id
    ts.mean = team2.first.mean
    ts.deviation = team2.first.deviation
    league[event.second_team_id] = ts
  end
end

class Store
  include EntityStore

  category :league
  entity League
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

  category :league

  handle RecordGameCreation do |command|
    result_event = GameCreationRecorded.follow(command)
    result_event.processed_time = clock.iso8601
    write.(result_event, stream_name(command.league_id))
  end
end

class TeamStrengthConsumer
  include Consumer::Postgres

  handler Handler
end

module Component
  def self.call
    league_command_stream_name = 'league:command'
    TeamStrengthConsumer.start(league_command_stream_name)
  end
end
