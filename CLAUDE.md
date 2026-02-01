# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
zig build              # Build the project
zig build run          # Build and run the server
zig build test         # Run all unit tests
```

## Environment Variables

- `PORT` - Server port (default: 8080)
- `HOST` - Server host (default: 0.0.0.0)
- `TOKENS_FILE` - Path to tokens.json (default: tokens.json)
- `REFRESH` - Refresh token for Fantasy Marca authentication

## Architecture

This is a REST API service that scrapes Fantasy Marca (fantasy.marca.com) and provides structured JSON responses.

### Core Services

**Browser** (`services/browser.zig`) - HTTP client using curl subprocess. Handles authentication headers (Cookie with refresh-token, X-Auth for community). Provides methods for both HTML pages (`feed()`, `market()`, `team()`, `standings()`) and AJAX JSON endpoints (`player()`, `playerGameweek()`, `offers()`, `communities()`, `topMarket()`).

**Scraper** (`services/scraper.zig`) - Parses responses from Browser. Uses string-based HTML parsing (no external library) with `extractBetween()` and `extractAttribute()` helpers. JSON parsing uses Zig's standard library. Key methods: `parseMarket()`, `parseTeam()`, `parseStandings()`, `parseFeedInfo()`, `parseBalanceInfo()`.

**TokenService** (`services/token.zig`) - Manages authentication tokens. Stores refresh token and per-community X-Auth tokens in `tokens.json`. Handles community switching.

### Request Flow

1. HTTP request → `httpz` server → Router → Handler
2. Handler creates Browser from ServerContext
3. Browser fetches from fantasy.marca.com with auth headers
4. Scraper parses HTML/JSON response
5. Handler applies filters/sorting, returns JSON

### Data Models

- `Player` - Base player with position, points, value, average, trend, streak, status
- `MarketPlayer` - Extends Player with owner, asked_price, offered_by, my_bid
- `TeamPlayer` - Extends Player with selected, being_sold flags
- `OfferPlayer` - Extends Player with best_bid, offered_by, date
- `User` - User info with position, points, value, bench players

### API Endpoints

All endpoints return JSON with structure: `{ status, data, meta }`.

- `GET /api/v1/market` - Market players with filtering (position, max_price, search, source, sort_by)
- `GET /api/v1/market/top` - Top market movers (gainers/losers) with `?interval=day|week|month`
- `GET /api/v1/team` - Own team (or `?user_id=` for other users)
- `GET /api/v1/standings` - League standings (total and gameweek)
- `GET /api/v1/players/:id` - Individual player details with participation stats
- `GET /api/v1/players/:id/gameweek/:gw_id` - Detailed per-match stats for a player
- `GET /api/v1/offers` - Received transfer offers
- `GET /api/v1/communities` - Available communities
- `POST /api/v1/communities/:id/switch` - Switch active community
- `POST /api/v1/auth/xauth` - Set X-Auth token for community

### HTML Parsing Patterns

The scraper uses marker-based extraction. Common patterns:
- `extractBetween(html, "class=\"name\">", "</div>")` - Content between markers
- `extractAttribute(html, "data-position")` - Attribute values
- `parseEuropeanNumber("1.234.567")` - Parse numbers with dot separators
- Player entries identified by `id="player-{id}"` pattern

### JSON Parsing Notes

Fantasy Marca AJAX endpoints return nested JSON structures:

**Player details** (`/ajax/sw/players`):
- `data.player.clause` is an **object**, not integer: `{value, floor, multiplier, shield, tier, percentage}`
- `data.player.clausesRanking` - integer rank (lower = cheaper clause)
- `data.player.owner` - object with `{id, name, avatar}`
- `data.player.transfer` - object with `{date, origin, price}`
- `data.player_extra` - object with `{matches, goals, cards}`

**Market top** (`/ajax/sw/market`):
- Returns `positive[]` (gainers) and `negative[]` (losers) arrays
- Each player has `market_ranks.day/week/month` for ranking position

### Clause System

Players have buyout clauses that can be activated to force a transfer:
- `clause.value` - actual clause price to pay
- `clause.floor` - minimum/base clause value
- `clause.multiplier` - multiplier applied to floor
- `clause.shield` - time remaining on clause protection (string like "20 horas 46 minutos" or 0)
- `clauses_rank` - league-wide ranking (1 = cheapest clause ratio)

When `shield > 0`, the clause cannot be activated until it expires.

### Player Details Endpoint

`GET /api/v1/players/:id` returns comprehensive player data:

**Basic info**: `name`, `position`, `points`, `value`, `avg`

**Participation tracking**:
- `matches` - games the player actually played
- `team_games` - games the player's team has played this season
- `participation_rate` - percentage (matches/team_games × 100)
- `starter` - whether player is predicted to start next match

**Performance splits**:
- `home_avg` - average points in home games
- `away_avg` - average points in away games

**Clause info**: `clause` (actual price), `clauses_rank` (1 = cheapest ratio)

Use `participation_rate` to filter out bench players with misleading averages (e.g., 7.7 avg but only 14% participation = bench warmer).

### Player Gameweek Endpoint

`GET /api/v1/players/:id/gameweek/:gw_id` returns detailed per-match statistics:

**Match info**: `home_team`, `away_team`, `home_goals`, `away_goals`, `is_home`, `status`

**Points by provider**: `fantasy`, `marca`, `md`, `as`, `mix`

**Detailed stats**:
- `minutes_played` - exact minutes on pitch
- `goals`, `assists`, `own_goals`
- `total_shots`, `shots_on_target`
- `total_passes`, `accurate_passes`, `pass_accuracy`
- `key_passes`, `big_chances_created`
- `total_clearances`, `total_interceptions`
- `duels_won`, `duels_lost`, `aerial_won`, `aerial_lost`
- `possession_lost`, `touches`
- `saves`, `goals_conceded` (for goalkeepers)
- `penalty_won`, `penalty_conceded`, `penalty_missed`, `penalty_saved`
- `expected_assists` (xA)

Gameweek IDs can be found in the player details `points[]` array from `/ajax/sw/players`.

### Player Rating System

The rating system (`services/rating.zig`) calculates a 0-100 score for each player based on multiple factors:

**Rating Components** (weights):
- **Value Trend (25%)** - Day/week/month value changes. Rising value = higher score.
- **Participation (20%)** - Games played vs team games. 90%+ = full marks, <70% penalized heavily.
- **Efficiency (15%)** - Points per million (PPM). Higher PPM = better value for money.
- **Performance (15%)** - Average points, position-adjusted (GK/DEF get bonus).
- **Form (15%)** - Recent streak sum. Higher recent scores = better form.
- **Clause (10%)** - Clause rank (70% weight) + clause/value ratio (30% weight). Lower rank = better bargain.

**Rating Tiers**:
- Elite: 90+
- Excellent: 80-89
- Good: 70-79
- Average: 55-69
- Below Average: 40-54
- Poor: <40

**Rating Endpoints**:

`GET /api/v1/ratings/player/:id` - Rate individual player with full details
- Returns overall score, tier, and component breakdown
- Always fetches detailed stats

`GET /api/v1/ratings/team?details=true` - Rate your team
- Returns rated players sorted by overall score
- Team average rating and tier
- `details=true` (default) fetches clause/participation data

`GET /api/v1/ratings/market?min_rating=60` - Rate market players
- Always fetches participation/clause details by default
- `skip_details=true` to skip detailed fetch (faster but less accurate)
- `min_rating` to filter low-rated players

`GET /api/v1/ratings/top?limit=50&position=0&owner=0` - Rate top players
- Uses `/ajax/sw/players` endpoint, always sorted by rating
- `position`: 0=all, 1=GK, 2=DEF, 3=MID, 4=FWD
- `owner`: 0=all, 1=free, 2=owned
- `limit`: max players to rate (default 50)

`GET /api/v1/players?order=0&position=0&owner=0` - Raw players list (no ratings)
- Returns raw data from Fantasy Marca `/ajax/sw/players`
- `order`: 0=points, 1=average, 2=streak, 3=value, 4=clause, 5=most_claused
- `position`: 0=all, 1=GK, 2=DEF, 3=MID, 4=FWD
- `owner`: 0=all, 1=free, 2=owned
- `offset`: pagination offset
- `name`: search by player name

**Important Notes**:
- All endpoints fetch full details by default (participation, clause, value changes)
- Use `skip_details=true` on market endpoint for faster but less accurate ratings
- Expensive elite players have lower PPM/efficiency scores but compensate with performance
- Use ratings to find undervalued players: high participation + good efficiency + rising value
