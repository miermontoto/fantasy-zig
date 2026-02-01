//! Fantasy Marca MCP Server
//!
//! An MCP (Model Context Protocol) server that exposes Fantasy Marca API
//! functionality as tools for AI applications.

const std = @import("std");
const mcp = @import("mcp");

// Import local modules
const config = @import("config.zig");
const TokenService = @import("services/token.zig").TokenService;
const Browser = @import("services/browser.zig").Browser;
const Scraper = @import("services/scraper.zig").Scraper;
const MarketPlayer = @import("models/player.zig").MarketPlayer;

// Global state for the MCP server
var global_allocator: std.mem.Allocator = undefined;
var global_token_service: *TokenService = undefined;

pub fn main() void {
    run() catch |err| {
        mcp.reportError(err);
    };
}

fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    global_allocator = allocator;

    // Initialize token service
    var token_service = TokenService.init(allocator) catch {
        std.debug.print("Failed to initialize token service\n", .{});
        return;
    };
    global_token_service = &token_service;

    // Create MCP server
    var server = mcp.Server.init(.{
        .name = "fantasy-marca",
        .version = "1.0.0",
        .title = "Fantasy Marca",
        .description = "Access Fantasy Marca data - teams, players, market, standings",
        .instructions = "Use the available tools to query Fantasy Marca data. Start with get_feed for an overview.",
        .allocator = allocator,
    });
    defer server.deinit();

    // Register tools
    try server.addTool(.{
        .name = "get_feed",
        .description = "Get feed overview with community info, balance, market highlights, and all communities",
        .title = "Get Feed",
        .handler = getFeedHandler,
    });

    try server.addTool(.{
        .name = "get_market",
        .description = "Get all players available in the market with optional filtering by position (PT/DF/MC/DL) or search term",
        .title = "Get Market",
        .handler = getMarketHandler,
    });

    try server.addTool(.{
        .name = "get_standings",
        .description = "Get league standings (total and gameweek rankings)",
        .title = "Get Standings",
        .handler = getStandingsHandler,
    });

    try server.addTool(.{
        .name = "get_team",
        .description = "Get your team's players with their stats and values",
        .title = "Get Team",
        .handler = getTeamHandler,
    });

    try server.addTool(.{
        .name = "get_communities",
        .description = "Get list of all your communities",
        .title = "Get Communities",
        .handler = getCommunitiesHandler,
    });

    try server.addTool(.{
        .name = "switch_community",
        .description = "Switch to a different community by ID",
        .title = "Switch Community",
        .handler = switchCommunityHandler,
    });

    try server.addTool(.{
        .name = "get_player",
        .description = "Get detailed information about a specific player by ID",
        .title = "Get Player Details",
        .handler = getPlayerHandler,
    });

    try server.addTool(.{
        .name = "get_offers",
        .description = "Get received offers for your players",
        .title = "Get Offers",
        .handler = getOffersHandler,
    });

    // Enable logging
    server.enableLogging();

    // Run the server via stdio
    try server.run(.stdio);
}

// Helper to build strings incrementally
fn StringBuilder(allocator: std.mem.Allocator) type {
    _ = allocator;
    return struct {
        data: std.ArrayList(u8),
        alloc: std.mem.Allocator,

        const Self = @This();

        pub fn init(a: std.mem.Allocator) Self {
            return .{
                .data = .{},
                .alloc = a,
            };
        }

        pub fn append(self: *Self, str: []const u8) void {
            for (str) |c| {
                self.data.append(self.alloc, c) catch {};
            }
        }

        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
            const s = std.fmt.allocPrint(self.alloc, fmt, args) catch return;
            defer self.alloc.free(s);
            self.append(s);
        }

        pub fn toSlice(self: *Self) []const u8 {
            return self.data.items;
        }
    };
}

fn getFeedHandler(allocator: std.mem.Allocator, _: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    var browser = Browser.init(allocator, global_token_service);
    defer browser.deinit();

    var scraper = Scraper.init(allocator, global_token_service.getCurrentCommunityInt());

    // Fetch feed HTML
    const html = browser.feed() catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(html);

    // Parse feed info
    const info = scraper.parseFeedInfo(html) catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };

    // Parse market players from feed
    const market_players = scraper.parseFeedMarket(html) catch &[_]MarketPlayer{};

    // Fetch communities
    const communities_json = browser.communities() catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(communities_json);

    const communities_result = scraper.parseCommunities(communities_json) catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };

    // Format response using allocPrint for each section
    var sections: [20][]const u8 = undefined;
    var section_count: usize = 0;

    sections[section_count] = std.fmt.allocPrint(allocator, "=== Feed Overview ===\nCommunity: {s}\nBalance: {s}\nCredits: {s}\nGameweek: {s}\nStatus: {s}\n", .{
        info.community,
        info.balance,
        info.credits,
        if (info.gameweek.len > 0) info.gameweek else "N/A",
        info.status,
    }) catch return mcp.tools.ToolError.OutOfMemory;
    section_count += 1;

    sections[section_count] = std.fmt.allocPrint(allocator, "\n=== Top Market Players ({d}) ===\n", .{market_players.len}) catch return mcp.tools.ToolError.OutOfMemory;
    section_count += 1;

    for (market_players) |player| {
        sections[section_count] = std.fmt.allocPrint(allocator, "- {s} ({s}) | {d} pts | {d}€\n", .{
            player.base.name,
            @tagName(player.base.position),
            player.base.points,
            player.base.value,
        }) catch continue;
        section_count += 1;
        if (section_count >= 18) break;
    }

    sections[section_count] = std.fmt.allocPrint(allocator, "\n=== Communities ({d}) ===\n", .{communities_result.communities.len}) catch return mcp.tools.ToolError.OutOfMemory;
    section_count += 1;

    for (communities_result.communities) |comm| {
        const current_marker: []const u8 = if (comm.current) " [CURRENT]" else "";
        sections[section_count] = std.fmt.allocPrint(allocator, "- {s} (ID: {d}) | {d}€{s}\n", .{
            comm.name,
            comm.id,
            comm.balance,
            current_marker,
        }) catch continue;
        section_count += 1;
        if (section_count >= 20) break;
    }

    // Concatenate all sections
    const result = std.mem.concat(allocator, u8, sections[0..section_count]) catch return mcp.tools.ToolError.OutOfMemory;

    return mcp.tools.textResult(allocator, result) catch return mcp.tools.ToolError.OutOfMemory;
}

fn getMarketHandler(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    var browser = Browser.init(allocator, global_token_service);
    defer browser.deinit();

    var scraper = Scraper.init(allocator, global_token_service.getCurrentCommunityInt());

    // Get optional filters
    const position_filter = mcp.tools.getString(args, "position");
    const search_filter = mcp.tools.getString(args, "search");

    // Fetch market HTML
    const html = browser.market() catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(html);

    // Parse market
    const market_result = scraper.parseMarket(html) catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };

    // Build result using ArrayList
    var lines: std.ArrayList([]const u8) = .{};

    const header = std.fmt.allocPrint(allocator, "=== Market Players ===\nBalance: {d}€ | Future: {d}€ | Max Debt: {d}€\n\n", .{
        market_result.info.current_balance,
        market_result.info.future_balance,
        market_result.info.max_debt,
    }) catch return mcp.tools.ToolError.OutOfMemory;
    lines.append(allocator, header) catch return mcp.tools.ToolError.OutOfMemory;

    var count: usize = 0;
    for (market_result.market) |player| {
        // Apply position filter
        if (position_filter) |pos| {
            const player_pos = @tagName(player.base.position);
            if (!std.ascii.eqlIgnoreCase(player_pos, pos)) continue;
        }

        // Apply search filter (simple substring match)
        if (search_filter) |search| {
            if (std.mem.indexOf(u8, player.base.name, search) == null) continue;
        }

        const status_str: []const u8 = if (player.base.status.isPresent()) @tagName(player.base.status) else "";
        var line: []const u8 = undefined;

        const player_id = player.base.id orelse "?";
        if (status_str.len > 0) {
            if (!std.mem.eql(u8, player.offered_by, config.FREE_AGENT)) {
                line = std.fmt.allocPrint(allocator, "ID:{s} | {s} ({s}) | {d} pts | avg {d:.1} | {d}€ | [{s}] | by {s}\n", .{
                    player_id,
                    player.base.name,
                    @tagName(player.base.position),
                    player.base.points,
                    player.base.average,
                    player.asked_price,
                    status_str,
                    player.offered_by,
                }) catch continue;
            } else {
                line = std.fmt.allocPrint(allocator, "ID:{s} | {s} ({s}) | {d} pts | avg {d:.1} | {d}€ | [{s}]\n", .{
                    player_id,
                    player.base.name,
                    @tagName(player.base.position),
                    player.base.points,
                    player.base.average,
                    player.asked_price,
                    status_str,
                }) catch continue;
            }
        } else {
            if (!std.mem.eql(u8, player.offered_by, config.FREE_AGENT)) {
                line = std.fmt.allocPrint(allocator, "ID:{s} | {s} ({s}) | {d} pts | avg {d:.1} | {d}€ | by {s}\n", .{
                    player_id,
                    player.base.name,
                    @tagName(player.base.position),
                    player.base.points,
                    player.base.average,
                    player.asked_price,
                    player.offered_by,
                }) catch continue;
            } else {
                line = std.fmt.allocPrint(allocator, "ID:{s} | {s} ({s}) | {d} pts | avg {d:.1} | {d}€\n", .{
                    player_id,
                    player.base.name,
                    @tagName(player.base.position),
                    player.base.points,
                    player.base.average,
                    player.asked_price,
                }) catch continue;
            }
        }

        lines.append(allocator, line) catch continue;
        count += 1;
    }

    const footer = std.fmt.allocPrint(allocator, "\nTotal: {d} players", .{count}) catch return mcp.tools.ToolError.OutOfMemory;
    lines.append(allocator, footer) catch return mcp.tools.ToolError.OutOfMemory;

    if (position_filter != null or search_filter != null) {
        const filter_note = std.fmt.allocPrint(allocator, " (filtered from {d})\n", .{market_result.market.len}) catch return mcp.tools.ToolError.OutOfMemory;
        lines.append(allocator, filter_note) catch return mcp.tools.ToolError.OutOfMemory;
    } else {
        lines.append(allocator, "\n") catch return mcp.tools.ToolError.OutOfMemory;
    }

    const result = std.mem.concat(allocator, u8, lines.items) catch return mcp.tools.ToolError.OutOfMemory;
    return mcp.tools.textResult(allocator, result) catch return mcp.tools.ToolError.OutOfMemory;
}

fn getStandingsHandler(allocator: std.mem.Allocator, _: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    var browser = Browser.init(allocator, global_token_service);
    defer browser.deinit();

    var scraper = Scraper.init(allocator, global_token_service.getCurrentCommunityInt());

    // Fetch standings HTML
    const html = browser.standings() catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(html);

    // Parse standings
    const standings = scraper.parseStandings(html) catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };

    var lines: std.ArrayList([]const u8) = .{};

    lines.append(allocator, "=== Total Standings ===\n") catch return mcp.tools.ToolError.OutOfMemory;
    for (standings.total) |user| {
        const me_marker: []const u8 = if (user.myself) " <-- YOU" else "";
        const pos = user.position orelse 0;
        const line = std.fmt.allocPrint(allocator, "{d}. {s} | {d} pts{s}\n", .{
            pos,
            user.name,
            user.points,
            me_marker,
        }) catch continue;
        lines.append(allocator, line) catch continue;
    }

    lines.append(allocator, "\n=== Gameweek Standings ===\n") catch return mcp.tools.ToolError.OutOfMemory;
    for (standings.gameweek) |user| {
        const me_marker: []const u8 = if (user.myself) " <-- YOU" else "";
        const pos = user.position orelse 0;
        const diff_str = user.diff orelse "";
        var line: []const u8 = undefined;
        if (diff_str.len > 0) {
            line = std.fmt.allocPrint(allocator, "{d}. {s} | {d} pts ({s}){s}\n", .{
                pos,
                user.name,
                user.points,
                diff_str,
                me_marker,
            }) catch continue;
        } else {
            line = std.fmt.allocPrint(allocator, "{d}. {s} | {d} pts{s}\n", .{
                pos,
                user.name,
                user.points,
                me_marker,
            }) catch continue;
        }
        lines.append(allocator, line) catch continue;
    }

    const result = std.mem.concat(allocator, u8, lines.items) catch return mcp.tools.ToolError.OutOfMemory;
    return mcp.tools.textResult(allocator, result) catch return mcp.tools.ToolError.OutOfMemory;
}

fn getTeamHandler(allocator: std.mem.Allocator, _: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    var browser = Browser.init(allocator, global_token_service);
    defer browser.deinit();

    var scraper = Scraper.init(allocator, global_token_service.getCurrentCommunityInt());

    // Fetch team HTML
    const html = browser.team() catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(html);

    // Parse team
    const team_result = scraper.parseTeam(html) catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };

    var lines: std.ArrayList([]const u8) = .{};

    const header = std.fmt.allocPrint(allocator, "=== My Team ===\nBalance: {d}€ | Future: {d}€ | Max Debt: {d}€\n\n", .{
        team_result.info.current_balance,
        team_result.info.future_balance,
        team_result.info.max_debt,
    }) catch return mcp.tools.ToolError.OutOfMemory;
    lines.append(allocator, header) catch return mcp.tools.ToolError.OutOfMemory;

    var total_value: i64 = 0;
    var total_points: i32 = 0;

    for (team_result.players) |player| {
        const selected_marker: []const u8 = if (player.selected) "[XI]" else "[BN]";
        const selling_marker: []const u8 = if (player.being_sold) " [SELLING]" else "";
        const status_str: []const u8 = if (player.base.status.isPresent()) @tagName(player.base.status) else "";
        const player_id = player.base.id orelse "?";

        var line: []const u8 = undefined;
        if (status_str.len > 0) {
            line = std.fmt.allocPrint(allocator, "{s} ID:{s} | {s} ({s}) | {d} pts | avg {d:.1} | {d}€ | [{s}]{s}\n", .{
                selected_marker,
                player_id,
                player.base.name,
                @tagName(player.base.position),
                player.base.points,
                player.base.average,
                player.base.value,
                status_str,
                selling_marker,
            }) catch continue;
        } else {
            line = std.fmt.allocPrint(allocator, "{s} ID:{s} | {s} ({s}) | {d} pts | avg {d:.1} | {d}€{s}\n", .{
                selected_marker,
                player_id,
                player.base.name,
                @tagName(player.base.position),
                player.base.points,
                player.base.average,
                player.base.value,
                selling_marker,
            }) catch continue;
        }

        lines.append(allocator, line) catch continue;
        total_value += player.base.value;
        total_points += player.base.points;
    }

    const footer = std.fmt.allocPrint(allocator, "\nTotal: {d} players | {d} pts | {d}€\n", .{
        team_result.players.len,
        total_points,
        total_value,
    }) catch return mcp.tools.ToolError.OutOfMemory;
    lines.append(allocator, footer) catch return mcp.tools.ToolError.OutOfMemory;

    const result = std.mem.concat(allocator, u8, lines.items) catch return mcp.tools.ToolError.OutOfMemory;
    return mcp.tools.textResult(allocator, result) catch return mcp.tools.ToolError.OutOfMemory;
}

fn getCommunitiesHandler(allocator: std.mem.Allocator, _: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    var browser = Browser.init(allocator, global_token_service);
    defer browser.deinit();

    var scraper = Scraper.init(allocator, global_token_service.getCurrentCommunityInt());

    // Fetch communities
    const json_response = browser.communities() catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json_response);

    // Parse communities
    const result_data = scraper.parseCommunities(json_response) catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };

    var lines: std.ArrayList([]const u8) = .{};

    lines.append(allocator, "=== Communities ===\n") catch return mcp.tools.ToolError.OutOfMemory;
    for (result_data.communities) |comm| {
        const current_marker: []const u8 = if (comm.current) " [CURRENT]" else "";
        const line1 = std.fmt.allocPrint(allocator, "ID: {d} | {s}{s}\n", .{
            comm.id,
            comm.name,
            current_marker,
        }) catch continue;
        lines.append(allocator, line1) catch continue;

        const line2 = std.fmt.allocPrint(allocator, "   Code: {s} | Mode: {s} | Competition: {d}\n", .{
            comm.code,
            comm.mode,
            comm.id_competition,
        }) catch continue;
        lines.append(allocator, line2) catch continue;

        const line3 = std.fmt.allocPrint(allocator, "   Balance: {d}€ | Offers: {d}\n\n", .{
            comm.balance,
            comm.offers,
        }) catch continue;
        lines.append(allocator, line3) catch continue;
    }

    const result = std.mem.concat(allocator, u8, lines.items) catch return mcp.tools.ToolError.OutOfMemory;
    return mcp.tools.textResult(allocator, result) catch return mcp.tools.ToolError.OutOfMemory;
}

fn switchCommunityHandler(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const community_id = mcp.tools.getString(args, "community_id") orelse {
        return mcp.tools.errorResult(allocator, "Missing required argument: community_id") catch return mcp.tools.ToolError.OutOfMemory;
    };

    var browser = Browser.init(allocator, global_token_service);
    defer browser.deinit();

    // Switch community
    browser.changeCommunity(community_id) catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };

    const msg = std.fmt.allocPrint(allocator, "Successfully switched to community {s}", .{community_id}) catch return mcp.tools.ToolError.OutOfMemory;
    return mcp.tools.textResult(allocator, msg) catch return mcp.tools.ToolError.OutOfMemory;
}

fn getPlayerHandler(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const player_id = mcp.tools.getString(args, "player_id") orelse {
        return mcp.tools.errorResult(allocator, "Missing required argument: player_id") catch return mcp.tools.ToolError.OutOfMemory;
    };

    var browser = Browser.init(allocator, global_token_service);
    defer browser.deinit();

    var scraper = Scraper.init(allocator, global_token_service.getCurrentCommunityInt());

    // Fetch player details
    const json_response = browser.player(player_id) catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json_response);

    // Parse player
    const player = scraper.parsePlayer(json_response) catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };

    var lines: std.ArrayList([]const u8) = .{};

    const header = std.fmt.allocPrint(allocator, "=== Player Details (ID: {s}) ===\n", .{player_id}) catch return mcp.tools.ToolError.OutOfMemory;
    lines.append(allocator, header) catch return mcp.tools.ToolError.OutOfMemory;

    if (player.name) |name| {
        const line = std.fmt.allocPrint(allocator, "Name: {s}\n", .{name}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.points) |pts| {
        const line = std.fmt.allocPrint(allocator, "Points: {d}\n", .{pts}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.value) |val| {
        const line = std.fmt.allocPrint(allocator, "Value: {d}€\n", .{val}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.avg) |avg| {
        const line = std.fmt.allocPrint(allocator, "Average: {d:.2}\n", .{avg}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.clause) |clause| {
        const line = std.fmt.allocPrint(allocator, "Clause: {d}€\n", .{clause}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.clauses_rank) |rank| {
        const line = std.fmt.allocPrint(allocator, "Clauses Rank: {d}\n", .{rank}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.goals) |goals| {
        const line = std.fmt.allocPrint(allocator, "Goals: {d}\n", .{goals}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.matches) |matches| {
        const line = std.fmt.allocPrint(allocator, "Matches: {d}\n", .{matches}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.participation_rate) |rate| {
        const line = std.fmt.allocPrint(allocator, "Participation: {d:.1}%\n", .{rate}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.home_avg) |avg| {
        const line = std.fmt.allocPrint(allocator, "Home Avg: {d:.2}\n", .{avg}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.away_avg) |avg| {
        const line = std.fmt.allocPrint(allocator, "Away Avg: {d:.2}\n", .{avg}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }
    if (player.starter) |starter| {
        const line = std.fmt.allocPrint(allocator, "Starter: {s}\n", .{if (starter) "Yes" else "No"}) catch "";
        if (line.len > 0) lines.append(allocator, line) catch {};
    }

    if (player.values.len > 0) {
        lines.append(allocator, "\nValue History:\n") catch {};
        for (player.values) |v| {
            const sign: []const u8 = if (v.change >= 0) "+" else "";
            const line = std.fmt.allocPrint(allocator, "  {s}: {d}€ ({s}{d})\n", .{
                @tagName(v.timespan),
                v.value,
                sign,
                v.change,
            }) catch continue;
            lines.append(allocator, line) catch continue;
        }
    }

    const result = std.mem.concat(allocator, u8, lines.items) catch return mcp.tools.ToolError.OutOfMemory;
    return mcp.tools.textResult(allocator, result) catch return mcp.tools.ToolError.OutOfMemory;
}

fn getOffersHandler(allocator: std.mem.Allocator, _: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    var browser = Browser.init(allocator, global_token_service);
    defer browser.deinit();

    var scraper = Scraper.init(allocator, global_token_service.getCurrentCommunityInt());

    // Fetch offers
    const json_response = browser.offers() catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(json_response);

    // Parse offers
    const offers_result = scraper.parseOffers(json_response) catch |err| {
        return mcp.tools.errorResult(allocator, @errorName(err)) catch return mcp.tools.ToolError.OutOfMemory;
    };

    var lines: std.ArrayList([]const u8) = .{};

    lines.append(allocator, "=== Received Offers ===\n") catch return mcp.tools.ToolError.OutOfMemory;

    if (offers_result.offers.len == 0) {
        lines.append(allocator, "No offers received.\n") catch return mcp.tools.ToolError.OutOfMemory;
    } else {
        for (offers_result.offers) |offer| {
            const offer_id = offer.base.id orelse "?";
            const line1 = std.fmt.allocPrint(allocator, "ID:{s} | {s} ({s}) | {d} pts | {d}€ value\n", .{
                offer_id,
                offer.base.name,
                @tagName(offer.base.position),
                offer.base.points,
                offer.base.value,
            }) catch continue;
            lines.append(allocator, line1) catch continue;

            const line2 = std.fmt.allocPrint(allocator, "   Best bid: {d}€ by {s} ({s})\n\n", .{
                offer.best_bid,
                offer.offered_by,
                offer.date,
            }) catch continue;
            lines.append(allocator, line2) catch continue;
        }
    }

    const footer = std.fmt.allocPrint(allocator, "Total: {d} offers\n", .{offers_result.offers.len}) catch return mcp.tools.ToolError.OutOfMemory;
    lines.append(allocator, footer) catch return mcp.tools.ToolError.OutOfMemory;

    const result = std.mem.concat(allocator, u8, lines.items) catch return mcp.tools.ToolError.OutOfMemory;
    return mcp.tools.textResult(allocator, result) catch return mcp.tools.ToolError.OutOfMemory;
}
