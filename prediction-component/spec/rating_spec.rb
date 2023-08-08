RSpec.describe "The system" do
  def random_id
    rand(1_000_000_000)
  end

  let!(:league_id) { random_id }
  let!(:store) { PredictionComponent::Store.build }

  def startup_sleep
    puts "Sleeping to wait for startup of server. Results are non-deterministic."
    sleep 3
  end

  def process_sleep
    puts "Sleeping to wait for processing of messages. Results are non-deterministic."
    sleep 3
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
    `echo "\n\n\n\n>>>>>>>>>> NEW TEST RUN <<<<<<<<<<" >> log/test.log`
    `date +"%Y-%m-%d %T" >> log/test.log`
    puts "*** Scrubbing message DB"
    `bundle exec mdb-recreate-db >> log/test.log`
    puts "*** Messages Status Before Tests"
    puts `bundle exec mdb-print-messages`

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

        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, first_team_id: team_id)
        league = read_version_from_store(league_id, version: 0)

        expect(league[team_id].mean).to be_between(1501, 2500).inclusive
        expect(league[team_id].deviation).to be_between(0, 999).inclusive
      end

      it "decreases ratings of the first team after that team looses a game" do
        team_id = random_id

        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, first_team_id: team_id, winning_team: 2)
        league = read_version_from_store(league_id, version: 0)

        expect(league[team_id].mean).to be_between(0, 1499).inclusive
        expect(league[team_id].deviation).to be_between(0, 999).inclusive
      end

      it "increases ratings of the second team after that team wins a game" do
        team_id = random_id

        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, second_team_id: team_id, winning_team: 2)
        league = read_version_from_store(league_id, version: 0)

        expect(league[team_id].mean).to be_between(1501, 2500).inclusive
        expect(league[team_id].deviation).to be_between(0, 999).inclusive
      end

      it "decreases ratings of the second team after that team looses a game" do
        team_id = random_id

        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, second_team_id: team_id)
        league = read_version_from_store(league_id, version: 0)

        expect(league[team_id].mean).to be_between(0, 1499).inclusive
        expect(league[team_id].deviation).to be_between(0, 999).inclusive
      end

      it "increases mean for subsequent wins, but less and less so" do
        first_team_id = random_id
        second_team_id = random_id

        league = read_version_from_store(league_id, version: :no_stream)
        mean_0 = league[first_team_id].mean

        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, first_team_id: first_team_id, second_team_id: second_team_id)

        league = read_version_from_store(league_id, version: 0)
        mean_1 = league[first_team_id].mean

        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, first_team_id: first_team_id, second_team_id: second_team_id)

        league = read_version_from_store(league_id, version: 1)
        mean_2 = league[first_team_id].mean

        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, first_team_id: first_team_id, second_team_id: second_team_id)

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

        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, first_team_id: first_team_id, second_team_id: second_team_id, winning_team: 2)
        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, first_team_id: second_team_id, second_team_id: third_team_id, winning_team: 2)
        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, first_team_id: third_team_id, second_team_id: fourth_team_id, winning_team: 2)

        league = read_version_from_store(league_id, version: 2)

        expect(league[first_team_id].mean < league[second_team_id].mean).to be_truthy
        expect(league[second_team_id].mean < league[third_team_id].mean).to be_truthy
        expect(league[third_team_id].mean < league[fourth_team_id].mean).to be_truthy
      end

      it "protects against command duplication" do
        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, game_id: 3)
        PredictionComponent::Client::RecordGameCreation.(league_id: league_id, game_id: 3)

        process_sleep
        _, version = store.fetch(league_id, include: :version)

        expect(version).to eq 0
      end
    end
  end
end