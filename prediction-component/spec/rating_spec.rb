RSpec.describe "The system" do
  let(:team_a_id) { rand(1_000_000_000) }
  let(:team_b_id) { rand(1_000_000_000) }
  let(:game_id) { rand(1_000_000_000) }
  let(:game) do
    game = RecordGameCreation.new

    game.game_id = game_id
    game.first_team_id = team_a_id
    game.second_team_id = team_b_id
    game.winning_team = @winning_team || 1
    game.time = Time.now.iso8601
    game
  end
  let(:command_stream_name) { "team_strength:command-#{team_a_id}" }
  let(:store) { Store.build }

  before(:context) do
    puts "*** Scrubbing message DB"
    `bundle exec mdb-recreate-db >> log/test.log`
    
    puts "*** Starting ComponentHost"
    fork { exec("ruby lib/service.rb >> log/test.log") }
    sleep 0.1
  end

  after (:context) do
      `ps ax | grep "ruby lib/service" | awk '{print "kill -s TERM " $1}' | sh`
  end

  describe "PredictionComponent" do
    it "defaults ratings to 1500 and 1000" do
      team_strength_a = store.fetch(team_a_id)
      expect(team_strength_a.mean).to eq 1500
      expect(team_strength_a.deviation).to eq 1000
    end

    it "increases ratings of the first team after that team wins a game" do
      @winning_team = 1
      Messaging::Postgres::Write.(game, command_stream_name)
      sleep 0.1

      team_strength_a = store.fetch(team_a_id)
      expect(team_strength_a.mean).to be_between(1501, 2500).inclusive
      expect(team_strength_a.deviation).to be_between(0, 999).inclusive
    end

    it "decreases ratings of the first team after that team looses a game" do
      @winning_team = 2
      Messaging::Postgres::Write.(game, command_stream_name)
      sleep 0.1

      team_strength_a = store.fetch(team_a_id)
      expect(team_strength_a.mean).to be_between(0, 1499).inclusive
      expect(team_strength_a.deviation).to be_between(0, 999).inclusive
    end

    it "increases ratings of the first team after that team wins a game" do
      @winning_team = 2
      Messaging::Postgres::Write.(game, command_stream_name)
      sleep 0.1

      team_strength_b = store.fetch(team_b_id)
      expect(team_strength_b.mean).to be_between(1501, 2500).inclusive
      expect(team_strength_b.deviation).to be_between(0, 999).inclusive
    end

    it "decreases ratings of the first team after that team looses a game" do
      @winning_team = 1
      Messaging::Postgres::Write.(game, command_stream_name)
      sleep 0.1

      team_strength_b = store.fetch(team_b_id)
      expect(team_strength_b.mean).to be_between(0, 1499).inclusive
      expect(team_strength_b.deviation).to be_between(0, 999).inclusive
    end
  end
end