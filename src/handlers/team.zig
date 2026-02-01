const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    var scraper = ctx.createScraper();

    // Check if requesting another user's team
    const qs = try req.query();
    const user_id = qs.get("user_id");

    if (user_id) |uid| {
        // Fetch other user's team via AJAX
        const json_response = browser.user(uid) catch |err| {
            try ctx.sendInternalError(res, "Failed to fetch user team", err);
            return;
        };
        defer ctx.allocator.free(json_response);

        const user = scraper.parseUser(json_response) catch |err| {
            try ctx.sendInternalError(res, "Failed to parse user data", err);
            return;
        };

        try ctx.sendSuccess(res, .{
            .user = .{
                .name = user.name,
                .points = user.points,
                .value = user.value,
                .average = user.average,
                .players_count = user.players_count,
                .user_img = user.user_img,
            },
            .players = user.bench,
        });
        return;
    }

    // Fetch own team HTML
    const html = browser.team() catch |err| {
        try ctx.sendInternalError(res, "Failed to fetch team", err);
        return;
    };
    defer ctx.allocator.free(html);

    // Parse team data including players
    const team_data = scraper.parseTeam(html) catch |err| {
        try ctx.sendInternalError(res, "Failed to parse team", err);
        return;
    };

    try ctx.sendSuccess(res, .{
        .players = team_data.players,
        .info = .{
            .current_balance = team_data.info.current_balance,
            .future_balance = team_data.info.future_balance,
            .max_debt = team_data.info.max_debt,
        },
        .count = team_data.players.len,
    });
}
