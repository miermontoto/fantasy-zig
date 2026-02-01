const std = @import("std");
const httpz = @import("httpz");
const config = @import("../config.zig");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");
const Scraper = @import("../services/scraper.zig").Scraper;
const RatingService = @import("../services/rating.zig").RatingService;
const PlayerStats = @import("../services/rating.zig").PlayerStats;
const PlayerRating = @import("../services/rating.zig").PlayerRating;
const RatingTier = @import("../services/rating.zig").RatingTier;
const ValueChange = @import("../models/player.zig").ValueChange;

/// Rate all market players with basic stats
/// GET /api/v1/ratings/market
pub fn handleMarket(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    const qs = try req.query();
    const skip_details_str = qs.get("skip_details");
    const fetch_details = if (skip_details_str) |d| !std.mem.eql(u8, d, "true") else true; // Default: always fetch details
    const min_rating_str = qs.get("min_rating");
    const min_rating: ?f32 = if (min_rating_str) |r| std.fmt.parseFloat(f32, r) catch null else null;

    // Fetch market HTML
    const html = browser.market() catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch market",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(html);

    // Parse market data
    var scraper = Scraper.init(ctx.allocator, null);
    const market_result = scraper.parseMarket(html) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse market",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };

    var rating_service = RatingService.init(null);
    var rated_players: std.ArrayList(RatedPlayer) = .{};

    for (market_result.market) |player| {
        var stats = PlayerStats{
            .id = player.base.id orelse "",
            .name = player.base.name,
            .position = @intFromEnum(player.base.position),
            .value = player.base.value,
            .points = player.base.points,
            .average = @floatCast(player.base.average),
            .streak_sum = player.base.streakSum(),
        };

        // Calculate PPM
        if (player.base.value > 0 and player.base.points > 0) {
            stats.ppm = @as(f32, @floatFromInt(player.base.points)) / @as(f32, @floatFromInt(player.base.value)) * 1_000_000.0;
        }

        // Optionally fetch detailed stats for each player
        if (fetch_details) {
            if (player.base.id) |id| {
                if (browser.player(id)) |details_json| {
                    defer ctx.allocator.free(details_json);
                    if (scraper.parsePlayer(details_json)) |details| {
                        stats.participation_rate = details.participation_rate;
                        stats.clause = details.clause;
                        stats.clauses_rank = details.clauses_rank;
                        stats.values = details.values;
                    } else |_| {}
                } else |_| {}
            }
        }

        const rating = rating_service.calculateRating(stats);

        // Apply min_rating filter
        if (min_rating) |min| {
            if (rating.overall < min) continue;
        }

        try rated_players.append(ctx.allocator, .{
            .id = stats.id,
            .name = stats.name,
            .position = stats.position,
            .value = stats.value,
            .points = stats.points,
            .average = stats.average,
            .ppm = stats.ppm,
            .participation_rate = stats.participation_rate,
            .rating = rating,
            .tier = RatingTier.fromScore(rating.overall).toString(),
            .owner = player.offered_by,
            .asked_price = player.asked_price,
        });
    }

    // Sort by overall rating descending
    const players_slice = rated_players.items;
    std.mem.sort(RatedPlayer, players_slice, {}, sortByRatingDesc);

    const timestamp = try date_utils.getCurrentTimestamp(ctx.allocator);
    defer ctx.allocator.free(timestamp);

    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = .{
            .players = players_slice,
            .count = players_slice.len,
        },
        .meta = .{
            .timestamp = timestamp,
            .details_fetched = fetch_details,
        },
    }, .{});
}

/// Rate the user's team
/// GET /api/v1/ratings/team
pub fn handleTeam(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    const qs = try req.query();
    const fetch_details_str = qs.get("details");
    const fetch_details = if (fetch_details_str) |d| std.mem.eql(u8, d, "true") else true; // Default true for team

    // Fetch team HTML
    const html = browser.team() catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch team",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(html);

    // Parse team data
    var scraper = Scraper.init(ctx.allocator, null);
    const team_result = scraper.parseTeam(html) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse team",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };

    var rating_service = RatingService.init(null);
    var rated_players: std.ArrayList(RatedTeamPlayer) = .{};
    var total_rating: f32 = 0;
    var count: u32 = 0;

    for (team_result.players) |player| {
        var stats = PlayerStats{
            .id = player.base.id orelse "",
            .name = player.base.name,
            .position = @intFromEnum(player.base.position),
            .value = player.base.value,
            .points = player.base.points,
            .average = @floatCast(player.base.average),
            .streak_sum = player.base.streakSum(),
        };

        // Calculate PPM
        if (player.base.value > 0 and player.base.points > 0) {
            stats.ppm = @as(f32, @floatFromInt(player.base.points)) / @as(f32, @floatFromInt(player.base.value)) * 1_000_000.0;
        }

        // Fetch detailed stats for each player
        if (fetch_details) {
            if (player.base.id) |id| {
                if (browser.player(id)) |details_json| {
                    defer ctx.allocator.free(details_json);
                    if (scraper.parsePlayer(details_json)) |details| {
                        stats.participation_rate = details.participation_rate;
                        stats.clause = details.clause;
                        stats.clauses_rank = details.clauses_rank;
                        stats.values = details.values;
                        // Update average and points from detailed stats
                        if (details.avg) |avg| stats.average = avg;
                        if (details.points) |pts| {
                            stats.points = pts;
                            // Recalculate PPM with updated points
                            if (stats.value > 0) {
                                stats.ppm = @as(f32, @floatFromInt(pts)) / @as(f32, @floatFromInt(stats.value)) * 1_000_000.0;
                            }
                        }
                    } else |_| {}
                } else |_| {}
            }
        }

        const rating = rating_service.calculateRating(stats);
        total_rating += rating.overall;
        count += 1;

        try rated_players.append(ctx.allocator, .{
            .id = stats.id,
            .name = stats.name,
            .position = stats.position,
            .value = stats.value,
            .points = stats.points,
            .average = stats.average,
            .ppm = stats.ppm,
            .participation_rate = stats.participation_rate,
            .rating = rating,
            .tier = RatingTier.fromScore(rating.overall).toString(),
            .selected = player.selected,
            .being_sold = player.being_sold,
        });
    }

    // Sort by overall rating descending
    const players_slice = rated_players.items;
    std.mem.sort(RatedTeamPlayer, players_slice, {}, sortByTeamRatingDesc);

    const avg_rating = if (count > 0) total_rating / @as(f32, @floatFromInt(count)) else 0;

    const timestamp = try date_utils.getCurrentTimestamp(ctx.allocator);
    defer ctx.allocator.free(timestamp);

    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = .{
            .players = players_slice,
            .count = players_slice.len,
            .team_average_rating = avg_rating,
            .team_tier = RatingTier.fromScore(avg_rating).toString(),
        },
        .meta = .{
            .timestamp = timestamp,
            .details_fetched = fetch_details,
        },
    }, .{});
}

/// Rate a single player with full details
/// GET /api/v1/ratings/player/:id
pub fn handlePlayer(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    const player_id = req.param("id") orelse {
        res.setStatus(.bad_request);
        try res.json(.{
            .status = "error",
            .message = "Player ID is required",
        }, .{});
        return;
    };

    // Fetch player details
    const details_json = browser.player(player_id) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch player",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(details_json);

    var scraper = Scraper.init(ctx.allocator, null);
    const details = scraper.parsePlayer(details_json) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse player",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };

    var stats = PlayerStats{
        .id = player_id,
        .name = details.name orelse "",
        .position = details.position,
        .value = details.value orelse 0,
        .points = details.points orelse 0,
        .average = details.avg orelse 0,
        .participation_rate = details.participation_rate,
        .matches = details.matches,
        .team_games = details.team_games,
        .clause = details.clause,
        .clauses_rank = details.clauses_rank,
        .values = details.values,
    };

    // Calculate PPM
    if (stats.value > 0 and stats.points > 0) {
        stats.ppm = @as(f32, @floatFromInt(stats.points)) / @as(f32, @floatFromInt(stats.value)) * 1_000_000.0;
    }

    var rating_service = RatingService.init(null);
    const rating = rating_service.calculateRating(stats);

    const timestamp = try date_utils.getCurrentTimestamp(ctx.allocator);
    defer ctx.allocator.free(timestamp);

    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = .{
            .id = player_id,
            .name = stats.name,
            .position = stats.position,
            .value = stats.value,
            .points = stats.points,
            .average = stats.average,
            .participation_rate = stats.participation_rate,
            .matches = stats.matches,
            .team_games = stats.team_games,
            .clause = stats.clause,
            .clauses_rank = stats.clauses_rank,
            .ppm = stats.ppm,
            .rating = .{
                .overall = rating.overall,
                .tier = RatingTier.fromScore(rating.overall).toString(),
                .components = .{
                    .value_trend = rating.value_trend,
                    .participation = rating.participation,
                    .efficiency = rating.efficiency,
                    .performance = rating.performance,
                    .form = rating.form,
                    .clause = rating.clause,
                },
                .raw = .{
                    .day_change = rating.raw.day_change,
                    .week_change = rating.raw.week_change,
                    .month_change = rating.raw.month_change,
                },
            },
        },
        .meta = .{
            .timestamp = timestamp,
        },
    }, .{});
}

/// Rate top players from the league
/// GET /api/v1/ratings/top?limit=50&position=0&owner=0&pool=100
/// position: 0=all, 1=GK, 2=DEF, 3=MID, 4=FWD
/// owner: 0=all, 1=free, 2=owned
/// limit: how many top-rated players to return (default 50)
/// pool: how many players to fetch and rate before selecting top (default 100)
/// Results are always sorted by rating (descending)
pub fn handleTop(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    const qs = try req.query();
    const position = if (qs.get("position")) |p| std.fmt.parseInt(u8, p, 10) catch 0 else 0;
    const owner = if (qs.get("owner")) |o| std.fmt.parseInt(u8, o, 10) catch 0 else 0;
    const limit: usize = if (qs.get("limit")) |l| std.fmt.parseInt(usize, l, 10) catch 50 else 50;
    const pool: usize = if (qs.get("pool")) |p| std.fmt.parseInt(usize, p, 10) catch 100 else 100;

    // Fetch players list (order=0 to get by points, we'll re-sort by rating)
    const json = browser.playersList(.{
        .order = 0, // Always fetch by points, then sort by rating
        .position = position,
        .owner = owner,
    }) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch players list",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(json);

    var scraper = Scraper.init(ctx.allocator, null);
    const list_result = scraper.parsePlayersList(json) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse players list",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };

    var rating_service = RatingService.init(null);
    var rated_players: std.ArrayList(RatedPlayer) = .{};
    var processed: usize = 0;

    // Process 'pool' players to find the best ones
    for (list_result.players) |player| {
        if (processed >= pool) break;

        // Calculate streak sum from players list data
        var streak_sum: i32 = 0;
        for (player.streak) |s| {
            streak_sum += s;
        }

        var stats = PlayerStats{
            .id = player.id,
            .name = player.name,
            .position = player.position,
            .value = player.value,
            .points = player.points,
            .average = player.avg,
            .clause = player.clause,
            .clauses_rank = player.clauses_rank,
            .streak_sum = streak_sum,
        };

        // Calculate PPM
        if (player.value > 0 and player.points > 0) {
            stats.ppm = @as(f32, @floatFromInt(player.points)) / @as(f32, @floatFromInt(player.value)) * 1_000_000.0;
        }

        // Fetch detailed stats for participation, value trends, and owner
        var owner_name: []const u8 = player.owner_name orelse config.FREE_AGENT;
        if (browser.player(player.id)) |details_json| {
            defer ctx.allocator.free(details_json);
            if (scraper.parsePlayer(details_json)) |details| {
                stats.participation_rate = details.participation_rate;
                stats.values = details.values;
                if (details.clause) |c| stats.clause = c;
                if (details.clauses_rank) |r| stats.clauses_rank = r;
                // Get owner from details if available
                if (details.owner_name) |on| {
                    owner_name = on;
                }
            } else |_| {}
        } else |_| {}

        const rating = rating_service.calculateRating(stats);

        try rated_players.append(ctx.allocator, .{
            .id = player.id,
            .name = player.name,
            .position = player.position,
            .value = player.value,
            .points = player.points,
            .average = player.avg,
            .ppm = stats.ppm,
            .participation_rate = stats.participation_rate,
            .rating = rating,
            .tier = RatingTier.fromScore(rating.overall).toString(),
            .owner = owner_name,
            .asked_price = 0,
        });

        processed += 1;
    }

    // Sort by overall rating descending
    const all_players = rated_players.items;
    std.mem.sort(RatedPlayer, all_players, {}, sortByRatingDesc);

    // Return only top 'limit' players
    const result_count = @min(limit, all_players.len);
    const top_players = all_players[0..result_count];

    const timestamp = try date_utils.getCurrentTimestamp(ctx.allocator);
    defer ctx.allocator.free(timestamp);

    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = .{
            .players = top_players,
            .count = top_players.len,
            .pool_size = processed,
            .total_available = list_result.total,
        },
        .meta = .{
            .timestamp = timestamp,
            .position = position,
            .owner = owner,
            .limit = limit,
            .pool = pool,
        },
    }, .{});
}

const RatedPlayer = struct {
    id: []const u8,
    name: []const u8,
    position: ?i32,
    value: i64,
    points: i32,
    average: f32,
    ppm: f32,
    participation_rate: ?f32,
    rating: PlayerRating,
    tier: []const u8,
    owner: []const u8,
    asked_price: i64,
};

const RatedTeamPlayer = struct {
    id: []const u8,
    name: []const u8,
    position: ?i32,
    value: i64,
    points: i32,
    average: f32,
    ppm: f32,
    participation_rate: ?f32,
    rating: PlayerRating,
    tier: []const u8,
    selected: bool,
    being_sold: bool,
};

fn sortByRatingDesc(_: void, a: RatedPlayer, b: RatedPlayer) bool {
    return a.rating.overall > b.rating.overall;
}

fn sortByTeamRatingDesc(_: void, a: RatedTeamPlayer, b: RatedTeamPlayer) bool {
    return a.rating.overall > b.rating.overall;
}
