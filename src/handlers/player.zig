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

    // Fetch player details via AJAX
    const json_response = browser.player(player_id) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch player details",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(json_response);

    // Parse player details
    const details = scraper.parsePlayer(json_response) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse player details",
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
            .id = player_id,
            .name = details.name,
            .position = details.position,
            .points = details.points,
            .value = details.value,
            .avg = details.avg,
            .starter = details.starter,
            .home_avg = details.home_avg,
            .away_avg = details.away_avg,
            .goals = details.goals,
            .matches = details.matches,
            .team_games = details.team_games,
            .participation_rate = details.participation_rate,
            .clause = details.clause,
            .clauses_rank = details.clauses_rank,
            .values = details.values,
        },
        .meta = .{
            .timestamp = timestamp,
        },
    }, .{});
}
