const std = @import("std");
const httpz = @import("httpz");
const server = @import("../http/server.zig");
const date_utils = @import("../utils/date.zig");
const Position = @import("../models/position.zig").Position;
const Scraper = @import("../services/scraper.zig").Scraper;
const MarketPlayer = @import("../models/player.zig").MarketPlayer;

pub fn handle(ctx: *server.ServerContext, req: *httpz.Request, res: *httpz.Response) !void {
    var browser = ctx.createBrowser();
    defer browser.deinit();

    // Get query parameters for filtering
    const qs = try req.query();
    const position_filter = qs.get("position");
    const max_price_str = qs.get("max_price");
    const search = qs.get("search");
    const source = qs.get("source"); // "free" or "users" or null for all
    const own_players_str = qs.get("own_players");
    const sort_by = qs.get("sort_by") orelse "points";
    const sort_dir = qs.get("sort_dir") orelse "desc";

    // Parse max_price filter
    const max_price: ?i64 = if (max_price_str) |price_str|
        std.fmt.parseInt(i64, price_str, 10) catch null
    else
        null;

    // Parse own_players filter
    const include_own = if (own_players_str) |own_str|
        std.mem.eql(u8, own_str, "true") or std.mem.eql(u8, own_str, "1")
    else
        true;

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
            .message = "Failed to parse market data",
            .@"error" = @errorName(err),
        }, .{});
        return;
    };

    // Apply filters
    var filtered_players: std.ArrayList(MarketPlayer) = .{};
    for (market_result.market) |player| {
        // Position filter
        if (position_filter) |pos_str| {
            const filter_pos = Position.fromString(pos_str);
            if (filter_pos) |fp| {
                if (player.base.position != fp) continue;
            }
        }

        // Max price filter
        if (max_price) |mp| {
            if (player.asked_price > mp) continue;
        }

        // Search filter (case-insensitive name match)
        if (search) |search_term| {
            const name_lower = try toLower(ctx.allocator, player.base.name);
            defer ctx.allocator.free(name_lower);
            const search_lower = try toLower(ctx.allocator, search_term);
            defer ctx.allocator.free(search_lower);
            if (std.mem.indexOf(u8, name_lower, search_lower) == null) continue;
        }

        // Source filter (free market vs user sales)
        if (source) |src| {
            if (std.mem.eql(u8, src, "free")) {
                if (!player.isFree()) continue;
            } else if (std.mem.eql(u8, src, "users")) {
                if (player.isFree()) continue;
            }
        }

        // Own players filter
        if (!include_own and player.own) continue;

        try filtered_players.append(ctx.allocator, player);
    }

    // Sort players
    const players_slice = filtered_players.items;
    if (std.mem.eql(u8, sort_by, "points")) {
        if (std.mem.eql(u8, sort_dir, "asc")) {
            std.mem.sort(MarketPlayer, players_slice, {}, sortByPointsAsc);
        } else {
            std.mem.sort(MarketPlayer, players_slice, {}, sortByPointsDesc);
        }
    } else if (std.mem.eql(u8, sort_by, "value")) {
        if (std.mem.eql(u8, sort_dir, "asc")) {
            std.mem.sort(MarketPlayer, players_slice, {}, sortByValueAsc);
        } else {
            std.mem.sort(MarketPlayer, players_slice, {}, sortByValueDesc);
        }
    } else if (std.mem.eql(u8, sort_by, "price")) {
        if (std.mem.eql(u8, sort_dir, "asc")) {
            std.mem.sort(MarketPlayer, players_slice, {}, sortByPriceAsc);
        } else {
            std.mem.sort(MarketPlayer, players_slice, {}, sortByPriceDesc);
        }
    } else if (std.mem.eql(u8, sort_by, "average")) {
        if (std.mem.eql(u8, sort_dir, "asc")) {
            std.mem.sort(MarketPlayer, players_slice, {}, sortByAvgAsc);
        } else {
            std.mem.sort(MarketPlayer, players_slice, {}, sortByAvgDesc);
        }
    }

    const timestamp = try date_utils.getCurrentTimestamp(ctx.allocator);
    defer ctx.allocator.free(timestamp);

    res.content_type = .JSON;
    try res.json(.{
        .status = "success",
        .data = .{
            .players = players_slice,
            .info = .{
                .current_balance = market_result.info.current_balance,
                .future_balance = market_result.info.future_balance,
                .max_debt = market_result.info.max_debt,
            },
            .count = players_slice.len,
        },
        .meta = .{
            .timestamp = timestamp,
        },
    }, .{});
}

fn toLower(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

fn sortByPointsDesc(_: void, a: MarketPlayer, b: MarketPlayer) bool {
    return a.base.points > b.base.points;
}

fn sortByPointsAsc(_: void, a: MarketPlayer, b: MarketPlayer) bool {
    return a.base.points < b.base.points;
}

fn sortByValueDesc(_: void, a: MarketPlayer, b: MarketPlayer) bool {
    return a.base.value > b.base.value;
}

fn sortByValueAsc(_: void, a: MarketPlayer, b: MarketPlayer) bool {
    return a.base.value < b.base.value;
}

fn sortByPriceDesc(_: void, a: MarketPlayer, b: MarketPlayer) bool {
    return a.asked_price > b.asked_price;
}

fn sortByPriceAsc(_: void, a: MarketPlayer, b: MarketPlayer) bool {
    return a.asked_price < b.asked_price;
}

fn sortByAvgDesc(_: void, a: MarketPlayer, b: MarketPlayer) bool {
    return a.base.average > b.base.average;
}

fn sortByAvgAsc(_: void, a: MarketPlayer, b: MarketPlayer) bool {
    return a.base.average < b.base.average;
}
