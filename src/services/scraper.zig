const std = @import("std");
const config = @import("../config.zig");
const Player = @import("../models/player.zig").Player;
const MarketPlayer = @import("../models/player.zig").MarketPlayer;
const TeamPlayer = @import("../models/player.zig").TeamPlayer;
const OfferPlayer = @import("../models/player.zig").OfferPlayer;
const TransferPlayer = @import("../models/player.zig").TransferPlayer;
const ValueChange = @import("../models/player.zig").ValueChange;
const Position = @import("../models/position.zig").Position;
const Status = @import("../models/status.zig").Status;
const Trend = @import("../models/trend.zig").Trend;
const User = @import("../models/user.zig").User;
const Community = @import("../models/community.zig").Community;
const Event = @import("../models/event.zig").Event;
const EventData = @import("../models/event.zig").EventData;
const EventType = @import("../models/event.zig").EventType;

pub const ScraperError = error{
    ParseError,
    InvalidJson,
    AjaxError,
    OutOfMemory,
};

pub const FeedResult = struct {
    events: []Event,
    market: []MarketPlayer,
    info: FeedInfo,
};

pub const FeedInfo = struct {
    community: []const u8,
    balance: []const u8,
    credits: []const u8,
    gameweek: []const u8,
    status: []const u8,
};

pub const MarketResult = struct {
    market: []MarketPlayer,
    info: MarketInfo,
};

pub const MarketInfo = struct {
    current_balance: i64,
    future_balance: i64,
    max_debt: i64,
};

pub const StandingsResult = struct {
    total: []User,
    gameweek: []User,
};

pub const TeamResult = struct {
    players: []TeamPlayer,
    info: MarketInfo,
};

pub const OffersResult = struct {
    offers: []OfferPlayer,
};

pub const CommunitiesResult = struct {
    communities: []Community,
};

pub const TopMarketResult = struct {
    positive: []Player,
    negative: []Player,
    last_value: i64,
    last_date: []const u8,
    diff: i64,
};

const OwnerRecord = @import("../models/player.zig").OwnerRecord;

pub const PlayerDetailsResult = struct {
    values: []ValueChange,
    owners: []const OwnerRecord,
    goals: ?i32,
    matches: ?i32,
    clauses_rank: ?i32,
    clause: ?i64,
};

pub const Scraper = struct {
    allocator: std.mem.Allocator,
    current_community_id: ?i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, current_community_id: ?i64) Self {
        return Self{
            .allocator = allocator,
            .current_community_id = current_community_id,
        };
    }

    // ========== JSON Parsing (AJAX responses) ==========

    /// Check AJAX response status and extract data
    fn checkAjaxResponse(self: *Self, json_str: []const u8) !std.json.Value {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{}) catch {
            return ScraperError.InvalidJson;
        };

        const root = parsed.value;
        if (root != .object) return ScraperError.InvalidJson;

        const status = root.object.get("status") orelse return ScraperError.InvalidJson;
        if (status == .string and std.mem.eql(u8, status.string, "error")) {
            return ScraperError.AjaxError;
        }

        const data = root.object.get("data") orelse return ScraperError.InvalidJson;
        return data;
    }

    /// Parse player details from /ajax/sw/players response
    pub fn parsePlayer(self: *Self, json_str: []const u8) !PlayerDetailsResult {
        const data = try self.checkAjaxResponse(json_str);
        if (data != .object) return ScraperError.ParseError;

        var result = PlayerDetailsResult{
            .values = &[_]ValueChange{},
            .owners = &[_]OwnerRecord{},
            .goals = null,
            .matches = null,
            .clauses_rank = null,
            .clause = null,
        };

        // Parse values array
        if (data.object.get("values")) |values_json| {
            if (values_json == .array) {
                var values: std.ArrayList(ValueChange) = .{};
                for (values_json.array.items) |item| {
                    if (item != .object) continue;

                    const time_str = if (item.object.get("time")) |t| (if (t == .string) t.string else "") else "";
                    const timespan = ValueChange.Timespan.fromSpanish(time_str) orelse continue;

                    const value = if (item.object.get("value")) |v| (if (v == .integer) v.integer else 0) else 0;
                    const change = if (item.object.get("change")) |c| (if (c == .integer) c.integer else 0) else 0;

                    try values.append(self.allocator, .{
                        .timespan = timespan,
                        .value = value,
                        .change = change,
                    });
                }
                result.values = try values.toOwnedSlice(self.allocator);
            }
        }

        // Parse player extra info
        if (data.object.get("player_extra")) |extra| {
            if (extra == .object) {
                if (extra.object.get("goals")) |g| {
                    result.goals = if (g == .integer) @intCast(g.integer) else null;
                }
                if (extra.object.get("matches")) |m| {
                    result.matches = if (m == .integer) @intCast(m.integer) else null;
                }
            }
        }

        // Parse player info
        if (data.object.get("player")) |player_info| {
            if (player_info == .object) {
                if (player_info.object.get("clausesRanking")) |cr| {
                    result.clauses_rank = if (cr == .integer) @intCast(cr.integer) else null;
                }
                if (player_info.object.get("clause")) |cl| {
                    result.clause = if (cl == .integer) cl.integer else null;
                }
            }
        }

        return result;
    }

    /// Parse offers from /ajax/sw/offers-received response
    pub fn parseOffers(self: *Self, json_str: []const u8) !OffersResult {
        const data = try self.checkAjaxResponse(json_str);
        if (data != .object) return ScraperError.ParseError;

        var offers: std.ArrayList(OfferPlayer) = .{};

        const offers_obj = data.object.get("offers") orelse return .{ .offers = &[_]OfferPlayer{} };
        if (offers_obj != .object) return .{ .offers = &[_]OfferPlayer{} };

        var it = offers_obj.object.iterator();
        while (it.next()) |entry| {
            const id = entry.key_ptr.*;
            const offer = entry.value_ptr.*;
            if (offer != .object) continue;

            const name = if (offer.object.get("name")) |n| (if (n == .string) n.string else "") else "";
            const position_val = if (offer.object.get("position")) |p| (if (p == .integer) p.integer else 1) else 1;
            const position_str = try std.fmt.allocPrint(self.allocator, "pos-{d}", .{position_val});
            const avg = if (offer.object.get("avg")) |a| (if (a == .float) a.float else 0.0) else 0.0;
            const value = if (offer.object.get("value")) |v| (if (v == .integer) v.integer else 0) else 0;
            const points = if (offer.object.get("points")) |p| (if (p == .integer) @as(i32, @intCast(p.integer)) else 0) else 0;
            const bid = if (offer.object.get("bid")) |b| (if (b == .integer) b.integer else 0) else 0;
            const uname = if (offer.object.get("uname")) |u| (if (u == .string) u.string else "") else "";
            const team_img = if (offer.object.get("teamLogoUrl")) |t| (if (t == .string) t.string else "") else "";
            const player_img = if (offer.object.get("photoUrl")) |p| (if (p == .string) p.string else "") else "";
            const date = if (offer.object.get("date")) |d| (if (d == .string) d.string else "") else "";

            // Parse streak
            var streak: std.ArrayList(i32) = .{};
            if (offer.object.get("streak")) |streak_arr| {
                if (streak_arr == .array) {
                    for (streak_arr.array.items) |s| {
                        if (s == .object) {
                            if (s.object.get("points")) |sp| {
                                if (sp == .integer) {
                                    try streak.append(self.allocator, @intCast(sp.integer));
                                }
                            }
                        }
                    }
                }
            }

            try offers.append(self.allocator, .{
                .base = .{
                    .id = id,
                    .name = name,
                    .position = Position.fromString(position_str) orelse .forward,
                    .average = avg,
                    .value = value,
                    .points = points,
                    .streak = try streak.toOwnedSlice(self.allocator),
                    .team_img = team_img,
                    .player_img = player_img,
                },
                .best_bid = bid,
                .offered_by = uname,
                .date = date,
            });
        }

        return .{ .offers = try offers.toOwnedSlice(self.allocator) };
    }

    /// Parse communities from /ajax/community-check response
    pub fn parseCommunities(self: *Self, json_str: []const u8) !CommunitiesResult {
        const data = try self.checkAjaxResponse(json_str);
        if (data != .object) return ScraperError.ParseError;

        var communities: std.ArrayList(Community) = .{};

        const communities_obj = data.object.get("communities") orelse return .{ .communities = &[_]Community{} };
        if (communities_obj != .object) return .{ .communities = &[_]Community{} };

        var it = communities_obj.object.iterator();
        while (it.next()) |entry| {
            const community = entry.value_ptr.*;
            if (community != .object) continue;

            const id = if (community.object.get("id")) |i| (if (i == .integer) i.integer else 0) else 0;
            const name = if (community.object.get("name")) |n| (if (n == .string) n.string else "") else "";
            const icon = if (community.object.get("community_icon")) |i| (if (i == .string) i.string else "") else "";
            const balance = if (community.object.get("balance")) |b| (if (b == .integer) b.integer else 0) else 0;
            const offer_count = if (community.object.get("offers")) |o| (if (o == .integer) @as(i32, @intCast(o.integer)) else 0) else 0;

            const is_current = if (self.current_community_id) |cid| (id == cid) else false;

            try communities.append(self.allocator, .{
                .id = id,
                .name = name,
                .icon = icon,
                .balance = balance,
                .offers = offer_count,
                .current = is_current,
            });
        }

        return .{ .communities = try communities.toOwnedSlice(self.allocator) };
    }

    /// Parse top market from /ajax/sw/market response
    pub fn parseTopMarket(self: *Self, json_str: []const u8, timespan: []const u8) !TopMarketResult {
        const data = try self.checkAjaxResponse(json_str);
        if (data != .object) return ScraperError.ParseError;

        var positive: std.ArrayList(Player) = .{};
        var negative: std.ArrayList(Player) = .{};

        // Get last/prev values
        const last = data.object.get("last") orelse return ScraperError.ParseError;
        const prev = data.object.get("prev") orelse return ScraperError.ParseError;
        if (last != .object or prev != .object) return ScraperError.ParseError;

        const last_value = if (last.object.get("value")) |v| (if (v == .integer) v.integer else 0) else 0;
        const last_date = if (last.object.get("date")) |d| (if (d == .string) d.string else "") else "";
        const prev_value = if (prev.object.get("value")) |v| (if (v == .integer) v.integer else 0) else 0;

        // Parse players
        const players_obj = data.object.get("players") orelse return ScraperError.ParseError;
        if (players_obj != .object) return ScraperError.ParseError;

        // Parse positive
        if (players_obj.object.get("positive")) |pos_arr| {
            if (pos_arr == .array) {
                var index: i32 = 1;
                for (pos_arr.array.items) |item| {
                    if (item != .object) continue;
                    const player = try self.parseTopMarketPlayer(item, timespan, index);
                    try positive.append(self.allocator, player);
                    index += 1;
                }
            }
        }

        // Parse negative
        if (players_obj.object.get("negative")) |neg_arr| {
            if (neg_arr == .array) {
                var index: i32 = 1;
                // Reverse iteration for negative
                var i: usize = neg_arr.array.items.len;
                while (i > 0) {
                    i -= 1;
                    const item = neg_arr.array.items[i];
                    if (item != .object) continue;
                    const player = try self.parseTopMarketPlayer(item, timespan, -index);
                    try negative.append(self.allocator, player);
                    index += 1;
                }
            }
        }

        return .{
            .positive = try positive.toOwnedSlice(self.allocator),
            .negative = try negative.toOwnedSlice(self.allocator),
            .last_value = last_value,
            .last_date = last_date,
            .diff = last_value - prev_value,
        };
    }

    fn parseTopMarketPlayer(self: *Self, item: std.json.Value, timespan: []const u8, rank: i32) !Player {
        _ = timespan;
        if (item != .object) return ScraperError.ParseError;

        const id_int = if (item.object.get("id")) |i| (if (i == .integer) i.integer else 0) else 0;
        const id = try std.fmt.allocPrint(self.allocator, "{d}", .{id_int});
        const name = if (item.object.get("name")) |n| (if (n == .string) n.string else "") else "";
        const position_val = if (item.object.get("position")) |p| (if (p == .integer) p.integer else 1) else 1;
        const position_str = try std.fmt.allocPrint(self.allocator, "pos-{d}", .{position_val});
        const value = if (item.object.get("value")) |v| (if (v == .integer) v.integer else 0) else 0;
        const diff = if (item.object.get("diff")) |d| (if (d == .integer) d.integer else 0) else 0;
        const team_img = if (item.object.get("teamLogoUrl")) |t| (if (t == .string) t.string else "") else "";
        const player_img = if (item.object.get("photoUrl")) |p| (if (p == .string) p.string else "") else "";

        return Player{
            .id = id,
            .name = name,
            .position = Position.fromString(position_str) orelse .forward,
            .value = value,
            .trend = Trend.fromValue(diff),
            .team_img = team_img,
            .player_img = player_img,
            .market_ranks = .{ .day = rank },
        };
    }

    /// Parse user data from /ajax/sw/users response
    pub fn parseUser(self: *Self, json_str: []const u8) !User {
        const data = try self.checkAjaxResponse(json_str);
        if (data != .object) return ScraperError.ParseError;

        var bench: std.ArrayList(TeamPlayer) = .{};

        // Parse team_now
        if (data.object.get("team_now")) |team| {
            if (team == .array) {
                for (team.array.items) |item| {
                    if (item != .object) continue;

                    const id_int = if (item.object.get("id")) |i| (if (i == .integer) i.integer else 0) else 0;
                    const id = try std.fmt.allocPrint(self.allocator, "{d}", .{id_int});
                    const name = if (item.object.get("name")) |n| (if (n == .string) n.string else "") else "";
                    const position_val = if (item.object.get("position")) |p| (if (p == .integer) p.integer else 1) else 1;
                    const position_str = try std.fmt.allocPrint(self.allocator, "pos-{d}", .{position_val});
                    const value = if (item.object.get("value")) |v| (if (v == .integer) v.integer else 0) else 0;
                    const avg = if (item.object.get("avg")) |a| (if (a == .float) a.float else 0.0) else 0.0;
                    const points = if (item.object.get("points")) |p| (if (p == .integer) @as(i32, @intCast(p.integer)) else 0) else 0;
                    const team_img = if (item.object.get("teamLogoUrl")) |t| (if (t == .string) t.string else "") else "";
                    const player_img = if (item.object.get("photoUrl")) |p| (if (p == .string) p.string else "") else "";
                    const status_val = if (item.object.get("status")) |s| (if (s == .string) s.string else null) else null;
                    const prev_value = if (item.object.get("prev_value")) |pv| (if (pv == .integer) pv.integer else value) else value;

                    // Parse streak
                    var streak: std.ArrayList(i32) = .{};
                    if (item.object.get("streak")) |streak_arr| {
                        if (streak_arr == .array) {
                            for (streak_arr.array.items) |s| {
                                if (s == .object) {
                                    if (s.object.get("points")) |sp| {
                                        if (sp == .integer) {
                                            try streak.append(self.allocator, @intCast(sp.integer));
                                        }
                                    }
                                }
                            }
                        }
                    }

                    try bench.append(self.allocator, .{
                        .base = .{
                            .id = id,
                            .name = name,
                            .position = Position.fromString(position_str) orelse .forward,
                            .value = value,
                            .average = avg,
                            .points = points,
                            .streak = try streak.toOwnedSlice(self.allocator),
                            .team_img = team_img,
                            .player_img = player_img,
                            .status = Status.fromString(status_val),
                            .trend = if (prev_value > value) Trend.down else Trend.up,
                        },
                    });
                }
            }
        }

        // Parse user info
        var user = User{
            .bench = try bench.toOwnedSlice(self.allocator),
        };

        if (data.object.get("userInfo")) |info| {
            if (info == .object) {
                user.name = if (info.object.get("name")) |n| (if (n == .string) n.string else "") else "";
                if (info.object.get("avatar")) |avatar| {
                    if (avatar == .object) {
                        user.user_img = if (avatar.object.get("pic")) |p| (if (p == .string) p.string else user.user_img) else user.user_img;
                    }
                }
            }
        }

        if (data.object.get("season")) |season| {
            if (season == .object) {
                user.points = if (season.object.get("points")) |p| (if (p == .integer) @as(i32, @intCast(p.integer)) else 0) else 0;
                user.average = if (season.object.get("avg")) |a| (if (a == .float) a.float else null) else null;
            }
        }

        if (data.object.get("value")) |v| {
            user.value = if (v == .integer) v.integer else null;
        }

        user.players_count = @intCast(user.bench.len);

        return user;
    }

    // ========== HTML Parsing ==========
    // Note: For full HTML parsing, we'd need an HTML parser library like rem.
    // For now, we'll use simple string searching for the most critical elements.

    /// Simple HTML text extraction between markers
    fn extractBetween(html: []const u8, start_marker: []const u8, end_marker: []const u8) ?[]const u8 {
        const start_idx = std.mem.indexOf(u8, html, start_marker) orelse return null;
        const content_start = start_idx + start_marker.len;
        const end_idx = std.mem.indexOf(u8, html[content_start..], end_marker) orelse return null;
        return html[content_start .. content_start + end_idx];
    }

    /// Extract attribute value from HTML tag
    fn extractAttribute(html: []const u8, attr_name: []const u8) ?[]const u8 {
        const attr_search = std.fmt.allocPrint(std.heap.page_allocator, "{s}=\"", .{attr_name}) catch return null;
        defer std.heap.page_allocator.free(attr_search);

        const start_idx = std.mem.indexOf(u8, html, attr_search) orelse return null;
        const value_start = start_idx + attr_search.len;
        const end_idx = std.mem.indexOf(u8, html[value_start..], "\"") orelse return null;
        return html[value_start .. value_start + end_idx];
    }

    /// Strip HTML tags from text
    fn stripTags(self: *Self, html: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .{};
        var in_tag = false;

        for (html) |c| {
            if (c == '<') {
                in_tag = true;
            } else if (c == '>') {
                in_tag = false;
            } else if (!in_tag) {
                try result.append(self.allocator, c);
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Trim whitespace and normalize spaces
    fn normalizeWhitespace(self: *Self, text: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .{};
        var last_was_space = true;

        for (text) |c| {
            const is_space = c == ' ' or c == '\t' or c == '\n' or c == '\r';
            if (is_space) {
                if (!last_was_space) {
                    try result.append(self.allocator, ' ');
                    last_was_space = true;
                }
            } else {
                try result.append(self.allocator, c);
                last_was_space = false;
            }
        }

        // Trim trailing space
        var slice = result.items;
        if (slice.len > 0 and slice[slice.len - 1] == ' ') {
            slice = slice[0 .. slice.len - 1];
        }
        // Trim leading space
        if (slice.len > 0 and slice[0] == ' ') {
            slice = slice[1..];
        }

        return try self.allocator.dupe(u8, slice);
    }

    /// Parse number from string with European formatting (1.000.000)
    fn parseEuropeanNumber(text: []const u8) i64 {
        var result: i64 = 0;
        for (text) |c| {
            if (c >= '0' and c <= '9') {
                result = result * 10 + @as(i64, c - '0');
            }
        }
        return result;
    }

    /// Parse basic feed info from HTML
    pub fn parseFeedInfo(self: *Self, html: []const u8) !FeedInfo {
        _ = self;
        var info = FeedInfo{
            .community = "",
            .balance = "",
            .credits = "",
            .gameweek = "",
            .status = "",
        };

        // Extract community name
        if (extractBetween(html, "feed-top-community", "</div>")) |section| {
            if (extractBetween(section, "<span>", "</span>")) |name| {
                info.community = name;
            }
        }

        // Extract balance
        if (extractBetween(html, "balance-real-current\">", "<")) |balance| {
            info.balance = balance;
        }

        // Extract credits
        if (extractBetween(html, "credits-count\">", "<")) |credits| {
            info.credits = credits;
        }

        // Extract gameweek
        if (extractBetween(html, "gameweek__name\">", "<")) |gw| {
            info.gameweek = gw;
        }

        // Extract gameweek status
        if (extractBetween(html, "gameweek__status\">", "<")) |status| {
            info.status = status;
        }

        return info;
    }

    /// Parse balance info from market/team HTML footer
    pub fn parseBalanceInfo(html: []const u8) MarketInfo {
        var info = MarketInfo{
            .current_balance = 0,
            .future_balance = 0,
            .max_debt = 0,
        };

        if (extractBetween(html, "balance-real-current\">", "<")) |balance| {
            info.current_balance = parseEuropeanNumber(balance);
        }

        if (extractBetween(html, "balance-real-future\">", "<")) |balance| {
            info.future_balance = parseEuropeanNumber(balance);
        }

        if (extractBetween(html, "balance-real-maxdebt\">", "<")) |balance| {
            info.max_debt = parseEuropeanNumber(balance);
        }

        return info;
    }

    /// Parse team players from /team HTML page
    pub fn parseTeam(self: *Self, html: []const u8) !TeamResult {
        var players: std.ArrayList(TeamPlayer) = .{};

        // Find the team list section
        const list_start = std.mem.indexOf(u8, html, "list-team") orelse return .{
            .players = &[_]TeamPlayer{},
            .info = parseBalanceInfo(html),
        };

        // Parse each player entry (format: id="player-{id}")
        var pos: usize = list_start;
        while (std.mem.indexOfPos(u8, html, pos, "id=\"player-")) |player_start| {
            // Extract player ID
            const id_start = player_start + 11; // len("id=\"player-")
            const id_end = std.mem.indexOfPos(u8, html, id_start, "\"") orelse break;
            const player_id = html[id_start..id_end];

            // Find the end of this player's entry (next player or end of list)
            const next_player = std.mem.indexOfPos(u8, html, id_end, "id=\"player-") orelse html.len;
            const player_html = html[player_start..next_player];

            // Extract player data
            const player = self.parseTeamPlayerHtml(player_id, player_html) catch {
                pos = id_end;
                continue;
            };

            try players.append(self.allocator, player);
            pos = next_player;
        }

        return .{
            .players = try players.toOwnedSlice(self.allocator),
            .info = parseBalanceInfo(html),
        };
    }

    fn parseTeamPlayerHtml(self: *Self, player_id: []const u8, player_html: []const u8) !TeamPlayer {
        // Extract team logo
        const team_img = extractBetween(player_html, "team-logo' width='20' height='20' src='", "'") orelse
            extractBetween(player_html, "team-logo' width='18' height='18' src='", "'") orelse "";

        // Extract position from data-position attribute
        const position_str = extractBetween(player_html, "data-position='", "'") orelse "4";
        const position = Position.fromString(position_str) orelse .forward;

        // Extract points
        const points_str = extractBetween(player_html, "class=\"points\">", "<") orelse "0";
        const points: i32 = std.fmt.parseInt(i32, std.mem.trim(u8, points_str, " \t\n\r"), 10) catch 0;

        // Extract player image
        const player_img = extractBetween(player_html, "player-avatar img\" src=\"", "\"") orelse
            extractBetween(player_html, "player-avatar--md", "loading") orelse "";
        const actual_player_img = if (std.mem.indexOf(u8, player_img, "src=\"")) |src_start|
            extractBetween(player_img[src_start..], "src=\"", "\"") orelse ""
        else
            player_img;

        // Extract status from SVG icon (injury, doubt, etc.)
        var status: Status = .none;
        if (std.mem.indexOf(u8, player_html, "#injury")) |_| {
            status = .injury;
        } else if (std.mem.indexOf(u8, player_html, "#doubt")) |_| {
            status = .doubt;
        } else if (std.mem.indexOf(u8, player_html, "#red")) |_| {
            status = .red;
        } else if (std.mem.indexOf(u8, player_html, "#five")) |_| {
            status = .five;
        }

        // Extract name (strip SVG icons and emoji divs)
        var name_section = extractBetween(player_html, "class=\"name\">", "</div>") orelse "";
        // Remove leading SVG tag if present (injury/doubt icons)
        if (std.mem.indexOf(u8, name_section, "</svg>")) |svg_end| {
            name_section = name_section[svg_end + 6 ..];
        }
        // Remove trailing clauses-ranking-emoji div if present
        if (std.mem.indexOf(u8, name_section, "<div class=\"clauses")) |div_start| {
            name_section = name_section[0..div_start];
        }
        const name = std.mem.trim(u8, name_section, " \t\n\r");

        // Extract value (European format like 20.457.000)
        const value_section = extractBetween(player_html, "<span class=\"euro\">", "</div>") orelse "";
        const value = parseEuropeanNumber(value_section);

        // Extract trend (arrow direction)
        const has_down_arrow = std.mem.indexOf(u8, player_html, "value-arrow red") != null;
        const has_up_arrow = std.mem.indexOf(u8, player_html, "value-arrow green") != null;
        const trend: Trend = if (has_down_arrow) .down else if (has_up_arrow) .up else .neutral;

        // Extract average
        const avg_str = extractBetween(player_html, "class=\"avg", "</div>") orelse "";
        const avg_value = extractBetween(avg_str, ">", "<") orelse "0";
        // Parse average (format: "5,9" - European decimal)
        var avg: f64 = 0.0;
        if (std.mem.indexOf(u8, avg_value, ",")) |comma_pos| {
            const int_part = std.fmt.parseFloat(f64, avg_value[0..comma_pos]) catch 0.0;
            const frac_str = avg_value[comma_pos + 1 ..];
            const frac_part = std.fmt.parseFloat(f64, frac_str) catch 0.0;
            const frac_divisor: f64 = @floatFromInt(std.math.pow(u64, 10, frac_str.len));
            avg = int_part + frac_part / frac_divisor;
        } else {
            avg = std.fmt.parseFloat(f64, std.mem.trim(u8, avg_value, " \t\n\r")) catch 0.0;
        }

        // Extract streak
        var streak: std.ArrayList(i32) = .{};
        var streak_pos: usize = 0;
        while (std.mem.indexOfPos(u8, player_html, streak_pos, "class=\"bg--")) |streak_start| {
            const streak_value_start = std.mem.indexOfPos(u8, player_html, streak_start, ">") orelse break;
            const streak_value_end = std.mem.indexOfPos(u8, player_html, streak_value_start, "</span>") orelse break;
            const streak_value_str = std.mem.trim(u8, player_html[streak_value_start + 1 .. streak_value_end], " \t\n\r");
            const streak_value = std.fmt.parseInt(i32, streak_value_str, 10) catch 0;
            try streak.append(self.allocator, streak_value);
            streak_pos = streak_value_end;
        }

        // Extract rival team logo
        const rival_img = extractBetween(player_html, "class=\"rival\"", "</div>") orelse "";
        const rival_team_img = extractBetween(rival_img, "src='", "'") orelse "";

        // Check if player is being sold
        const being_sold = std.mem.indexOf(u8, player_html, "btn-sale") != null and
            std.mem.indexOf(u8, player_html, "En venta") != null;

        // Check if player is selected (in starting lineup)
        const selected = std.mem.indexOf(u8, player_html, "selected") != null;

        // Allocate and copy the player ID
        const id_copy = try self.allocator.dupe(u8, player_id);

        return TeamPlayer{
            .base = .{
                .id = id_copy,
                .name = name,
                .position = position,
                .value = value,
                .average = avg,
                .points = points,
                .streak = try streak.toOwnedSlice(self.allocator),
                .team_img = team_img,
                .player_img = actual_player_img,
                .rival_img = rival_team_img,
                .trend = trend,
                .status = status,
            },
            .selected = selected,
            .being_sold = being_sold,
            .own = true,
        };
    }
};
