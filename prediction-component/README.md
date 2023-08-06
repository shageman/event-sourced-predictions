# PredictionComponent

## What's currently working

* defaults ratings to 1500 and 1000
* increases ratings of the first team after that team wins a game
* decreases ratings of the first team after that team looses a game
* increases ratings of the first team after that team wins a game
* decreases ratings of the first team after that team looses a game

## Todo

* use trueskill for rating increase / decrease
* implement game deletions
* implement game updates

## Continuous Testing

```
cd prediction-component
fswatch -o lib spec | xargs -n1 -I{} bundle exec rspec
```