# PredictionComponent

## What's currently working

* defaults ratings to 1500 mean and 1000 deviation
* increases rating mean of the first team after that team wins a game
* decreases rating mean of the first team after that team looses a game
* increases rating mean of the second team after that team wins a game
* decreases rating mean of the second team after that team looses a game
* increases rating mean for subsequent wins, but less and less so
* works for many teams
* protects against game recording duplication

## Todo

* implement game deletions
* implement game updates

## Continuous Testing

```
cd prediction-component
fswatch -o lib spec | xargs -n1 -I{} bundle exec rspec
```