const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    var scraper = ctx.createScraper();

    // Get player ID from URL parameter
    const player_id = req.param("id") orelse {
        res.setStatus(.bad_request);
        try res.json(.{
            .status = "error",
            .message = "Player ID is required",
        }, .{});
        return;
    };

    // Get gameweek ID from URL parameter
    const gameweek_id = req.param("gameweek") orelse {
        res.setStatus(.bad_request);
        try res.json(.{
            .status = "error",
            .message = "Gameweek ID is required",
        }, .{});
        return;
    };

    // Fetch player gameweek details via AJAX
    const json_response = browser.playerGameweek(player_id, gameweek_id) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch player gameweek details",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(json_response);

    // Parse player gameweek details
    const details = scraper.parsePlayerGameweek(json_response) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse player gameweek details",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };

    const timestamp = try date_utils.getCurrentTimestamp(ctx.allocator);
    defer ctx.allocator.free(timestamp);

    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = .{
            .id = details.id,
            .name = details.name,
            .position = details.position,
            .gameweek = details.gameweek,
            .minutes_played = details.minutes_played,
            .match = .{
                .home_team = details.home_team,
                .away_team = details.away_team,
                .home_goals = details.home_goals,
                .away_goals = details.away_goals,
                .is_home = details.is_home,
                .status = details.match_status,
            },
            .points = .{
                .fantasy = details.points_fantasy,
                .marca = details.points_marca,
                .md = details.points_md,
                .@"as" = details.points_as,
                .mix = details.points_mix,
            },
            .stats = .{
                .minutes_played = details.stats.minutes_played,
                .goals = details.stats.goals,
                .assists = details.stats.assists,
                .own_goals = details.stats.own_goals,
                .yellow_card = details.stats.yellow_card,
                .red_card = details.stats.red_card,
                .total_shots = details.stats.total_shots,
                .shots_on_target = details.stats.shots_on_target,
                .key_passes = details.stats.key_passes,
                .big_chances_created = details.stats.big_chances_created,
                .total_passes = details.stats.total_passes,
                .accurate_passes = details.stats.accurate_passes,
                .pass_accuracy = if (details.stats.total_passes != null and details.stats.accurate_passes != null and details.stats.total_passes.? > 0)
                    @as(f32, @floatFromInt(details.stats.accurate_passes.?)) / @as(f32, @floatFromInt(details.stats.total_passes.?)) * 100.0
                else
                    null,
                .total_long_balls = details.stats.total_long_balls,
                .accurate_long_balls = details.stats.accurate_long_balls,
                .total_clearances = details.stats.total_clearances,
                .total_interceptions = details.stats.total_interceptions,
                .duels_won = details.stats.duels_won,
                .duels_lost = details.stats.duels_lost,
                .aerial_won = details.stats.aerial_won,
                .aerial_lost = details.stats.aerial_lost,
                .possession_lost = details.stats.possession_lost,
                .touches = details.stats.touches,
                .saves = details.stats.saves,
                .goals_conceded = details.stats.goals_conceded,
                .penalty_won = details.stats.penalty_won,
                .penalty_conceded = details.stats.penalty_conceded,
                .penalty_missed = details.stats.penalty_missed,
                .penalty_saved = details.stats.penalty_saved,
                .expected_assists = details.stats.expected_assists,
            },
        },
        .meta = .{
            .timestamp = timestamp,
        },
    }, .{});
}
