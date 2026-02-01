# Fantasy Team Analysis

Analyze my fantasy team and provide strategic recommendations using the API at localhost:8080.

## Analysis Steps

1. **Current Position Assessment**
   - Fetch standings to see league position and gaps
   - Get team composition and balance
   - Check community/gameweek context

2. **Squad Health Check**
   - Identify injured/suspended players (status != none)
   - Find underperformers (low average relative to value)
   - Check negative trends and weak streaks

3. **Market Intelligence**
   - Find high-value free agents (best PPM ratio)
   - Track rising stars from market/top endpoint
   - Identify budget opportunities

4. **Competitive Analysis**
   - Scout top rival teams
   - Review incoming offers

5. **Recommendations**
   - Players to sell (underperformers, good offers, negative trends)
   - Players to buy (rising value, high average, good form)
   - Position gaps to fill

## API Endpoints to Use

```bash
curl localhost:8080/api/v1/standings
curl localhost:8080/api/v1/team
curl localhost:8080/api/v1/feed
curl "localhost:8080/api/v1/market?source=free&sort_by=average&sort_dir=desc"
curl "localhost:8080/api/v1/market/top?interval=week"
curl localhost:8080/api/v1/offers
```

## Evaluation Criteria

| Factor | Weight |
|--------|--------|
| Average points/gameweek | 30% |
| Recent form (streak) | 25% |
| Value trend | 20% |
| Fitness status | 15% |
| Price efficiency (PPM) | 10% |

Provide actionable buy/sell recommendations with specific player names and reasoning.
