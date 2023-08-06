RSpec.describe "The system" do
  let(:league_id) { rand(1_000_000_000) }
  let(:command_stream_name) { "league:command-#{league_id}" }
  let(:store) { Store.build }

  def startup_sleep
    sleep 1
  end

  def process_sleep
    sleep 0.3
  end

  def random_id
    rand(1_000_000_000)
  end

  def game(game_id: random_id, first_team_id: random_id, second_team_id: random_id, winning_team: 1)
    game = RecordGameCreation.new

    game.league_id = league_id
    game.game_id = game_id
    game.first_team_id = first_team_id
    game.second_team_id = second_team_id
    game.winning_team = winning_team

    game.time = Time.now.iso8601

    game
  end

  def read_version_from_store(id, version:, max_tries: 50)
    tries = 0
    while true do
      tries += 1
      result, actual_version = store.fetch(id, include: :version)
      if version == actual_version
        break 
      elsif tries >= max_tries
        raise "Didn't read expected version. Expected: #{version}. Got: #{actual_version}"
      else
        sleep 0.05
      end
    end
    result
  end

  before(:context) do
    puts "*** Scrubbing message DB"
    `bundle exec mdb-recreate-db >> log/test.log`
    
    puts "*** Starting ComponentHost"
    fork { exec("ruby lib/service.rb >> log/test.log") }
    startup_sleep
  end

  after (:context) do
      `ps ax | grep "ruby lib/service" | awk '{print "kill -s TERM " $1}' | sh`
  end

  describe "PredictionComponent" do
    it "defaults ratings to 1500 and 1000" do
      team_id = random_id

      league = read_version_from_store(league_id, version: :no_stream)

      expect(league[team_id].mean).to eq 1500
      expect(league[team_id].deviation).to eq 1000
    end

    describe "effects of winning and loosing" do
      it "increases ratings of the first team after that team wins a game" do
        team_id = random_id

        Messaging::Postgres::Write.(game(first_team_id: team_id), command_stream_name)
        league = read_version_from_store(league_id, version: 0)

        # league, version = store.fetch(league_id, include: :version)
        # pp version
        expect(league[team_id].mean).to be_between(1501, 2500).inclusive
        expect(league[team_id].deviation).to be_between(0, 999).inclusive
      end

      it "decreases ratings of the first team after that team looses a game" do
        team_id = random_id

        Messaging::Postgres::Write.(game(first_team_id: team_id, winning_team: 2), command_stream_name)
        league = read_version_from_store(league_id, version: 0)

        expect(league[team_id].mean).to be_between(0, 1499).inclusive
        expect(league[team_id].deviation).to be_between(0, 999).inclusive
      end

      it "increases ratings of the second team after that team wins a game" do
        team_id = random_id

        Messaging::Postgres::Write.(game(second_team_id: team_id, winning_team: 2), command_stream_name)
        league = read_version_from_store(league_id, version: 0)

        expect(league[team_id].mean).to be_between(1501, 2500).inclusive
        expect(league[team_id].deviation).to be_between(0, 999).inclusive
      end

      it "decreases ratings of the second team after that team looses a game" do
        team_id = random_id

        Messaging::Postgres::Write.(game(second_team_id: team_id), command_stream_name)
        league = read_version_from_store(league_id, version: 0)

        expect(league[team_id].mean).to be_between(0, 1499).inclusive
        expect(league[team_id].deviation).to be_between(0, 999).inclusive
      end

      it "increases mean for subsequent wins, but less and less so" do
        first_team_id = random_id
        second_team_id = random_id

        league = read_version_from_store(league_id, version: :no_stream)
        mean_0 = league[first_team_id].mean

        Messaging::Postgres::Write.(game(
            first_team_id: first_team_id, 
            second_team_id: second_team_id, 
            winning_team: 1
          ), command_stream_name
        )

        league = read_version_from_store(league_id, version: 0)
        mean_1 = league[first_team_id].mean

        Messaging::Postgres::Write.(game(
            first_team_id: first_team_id, 
            second_team_id: second_team_id, 
            winning_team: 1
          ), command_stream_name
        )

        league = read_version_from_store(league_id, version: 1)
        mean_2 = league[first_team_id].mean

        Messaging::Postgres::Write.(game(
            first_team_id: first_team_id, 
            second_team_id: second_team_id, 
            winning_team: 1
          ), command_stream_name
        )

        league = read_version_from_store(league_id, version: 2)
        mean_3 = league[first_team_id].mean

        expect(mean_0 < mean_1).to be_truthy
        expect(mean_1 < mean_2).to be_truthy
        expect(mean_2 < mean_3).to be_truthy

        expect([mean_0 - mean_1, mean_1 - mean_2, mean_2 - mean_3]).to eq [mean_0 - mean_1, mean_1 - mean_2, mean_2 - mean_3].sort
      end

      it "works for many teams" do
        first_team_id = random_id
        second_team_id = random_id
        third_team_id = random_id
        fourth_team_id = random_id

        Messaging::Postgres::Write.(game(
            first_team_id: first_team_id, 
            second_team_id: second_team_id, 
            winning_team: 2
          ), command_stream_name
        )

        Messaging::Postgres::Write.(game(
            first_team_id: second_team_id, 
            second_team_id: third_team_id, 
            winning_team: 2
          ), command_stream_name
        )

        Messaging::Postgres::Write.(game(
            first_team_id: third_team_id, 
            second_team_id: fourth_team_id, 
            winning_team: 2
          ), command_stream_name
        )

        league = read_version_from_store(league_id, version: 2)

        expect(league[first_team_id].mean < league[second_team_id].mean).to be_truthy
        expect(league[second_team_id].mean < league[third_team_id].mean).to be_truthy
        expect(league[third_team_id].mean < league[fourth_team_id].mean).to be_truthy
      end
    end
  end
end