const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");
const Browser = @import("../services/browser.zig").Browser;
const Scraper = @import("../services/scraper.zig").Scraper;

/// GET /api/v1/players - List all players with filters
/// Returns raw player data from Fantasy Marca API
///
/// Query params:
/// - order: 0=points, 1=average, 2=streak, 3=value, 4=clause, 5=most_claused
/// - position: 0=all, 1=GK, 2=DEF, 3=MID, 4=FWD
/// - owner: 0=all, 1=free, 2=owned
/// - offset: pagination offset
/// - name: search by name
pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    const qs = try req.query();

    // Parse query parameters
    const position = if (qs.get("position")) |p| std.fmt.parseInt(u8, p, 10) catch 0 else 0;
    const order = if (qs.get("order")) |o| std.fmt.parseInt(u8, o, 10) catch 0 else 0;
    const offset = if (qs.get("offset")) |o| std.fmt.parseInt(u32, o, 10) catch 0 else 0;
    const owner = if (qs.get("owner")) |o| std.fmt.parseInt(u8, o, 10) catch 0 else 0;
    const name = qs.get("name") orelse "";

    const options = Browser.PlayersListOptions{
        .position = position,
        .order = order,
        .offset = offset,
        .owner = owner,
        .name = name,
    };

    // Fetch players list
    const json = browser.playersList(options) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to fetch players list",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };
    defer ctx.allocator.free(json);

    // Parse players list
    var scraper = Scraper.init(ctx.allocator, null);
    const result = scraper.parsePlayersList(json) catch |err| {
        res.setStatus(.internal_server_error);
        try res.json(.{
            .status = "error",
            .message = "Failed to parse players list",
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
            .players = result.players,
            .total = result.total,
            .offset = result.offset,
            .count = result.players.len,
        },
        .meta = .{
            .timestamp = timestamp,
            .filters = .{
                .order = order,
                .position = position,
                .owner = owner,
                .offset = offset,
            },
        },
    }, .{});
}
