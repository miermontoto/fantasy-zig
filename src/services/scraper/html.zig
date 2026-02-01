//! parsing de respuestas HTML (páginas de Fantasy Marca)
//! contiene funciones para parsear /market, /team, /standings, /feed

const std = @import("std");
const config = @import("../../config.zig");
const types = @import("types.zig");
const helpers = @import("helpers.zig");
const MarketPlayer = @import("../../models/player.zig").MarketPlayer;
const TeamPlayer = @import("../../models/player.zig").TeamPlayer;
const Position = @import("../../models/position.zig").Position;
const Status = @import("../../models/status.zig").Status;
const Trend = @import("../../models/trend.zig").Trend;
const User = @import("../../models/user.zig").User;

// re-importar tipos del módulo
const ScraperError = types.ScraperError;
const FeedInfo = types.FeedInfo;
const MarketResult = types.MarketResult;
const MarketInfo = types.MarketInfo;
const StandingsResult = types.StandingsResult;
const TeamResult = types.TeamResult;

/// Parse basic feed info from HTML
pub fn parseFeedInfo(html: []const u8) FeedInfo {
    var info = FeedInfo{
        .community = "",
        .balance = "",
        .credits = "",
        .gameweek = "",
        .status = "",
    };

    // Extract community name from feed-top-community .name span
    if (std.mem.indexOf(u8, html, "feed-top-community")) |start| {
        const section = html[start..@min(start + 500, html.len)];
        if (helpers.extractBetween(section, "<span>", "</span>")) |name| {
            info.community = std.mem.trim(u8, name, " \t\n\r");
        }
    }

    // Extract balance (handle space before ">")
    if (helpers.extractBetween(html, "balance-real-current \">", "<")) |balance| {
        info.balance = std.mem.trim(u8, balance, " \t\n\r");
    } else if (helpers.extractBetween(html, "balance-real-current\">", "<")) |balance| {
        info.balance = std.mem.trim(u8, balance, " \t\n\r");
    }

    // Extract credits
    if (helpers.extractBetween(html, "credits-count \">", "<")) |credits| {
        info.credits = std.mem.trim(u8, credits, " \t\n\r");
    } else if (helpers.extractBetween(html, "credits-count\">", "<")) |credits| {
        info.credits = std.mem.trim(u8, credits, " \t\n\r");
    }

    // Extract gameweek name
    if (std.mem.indexOf(u8, html, "gameweek__name")) |gw_start| {
        const gw_section = html[gw_start..@min(gw_start + 200, html.len)];
        if (std.mem.indexOf(u8, gw_section, ">")) |gt| {
            if (std.mem.indexOfPos(u8, gw_section, gt, "<")) |lt| {
                const gw_text = std.mem.trim(u8, gw_section[gt + 1 .. lt], " \t\n\r");
                if (gw_text.len > 0) {
                    info.gameweek = gw_text;
                }
            }
        }
    }

    // Extract gameweek status
    if (std.mem.indexOf(u8, html, "gameweek__status")) |status_start| {
        const status_section = html[status_start..@min(status_start + 300, html.len)];
        if (std.mem.indexOf(u8, status_section, ">")) |gt| {
            if (std.mem.indexOfPos(u8, status_section, gt, "<")) |lt| {
                const status_text = std.mem.trim(u8, status_section[gt + 1 .. lt], " \t\n\r");
                if (status_text.len > 0) {
                    info.status = status_text;
                }
            }
        }
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

    if (helpers.extractBetween(html, "balance-real-current \">", "<")) |balance| {
        info.current_balance = helpers.parseBalanceValue(balance);
    } else if (helpers.extractBetween(html, "balance-real-current\">", "<")) |balance| {
        info.current_balance = helpers.parseBalanceValue(balance);
    }

    if (helpers.extractBetween(html, "balance-real-future \">", "<")) |balance| {
        info.future_balance = helpers.parseBalanceValue(balance);
    } else if (helpers.extractBetween(html, "balance-real-future\">", "<")) |balance| {
        info.future_balance = helpers.parseBalanceValue(balance);
    }

    if (helpers.extractBetween(html, "balance-real-maxdebt \">", "<")) |balance| {
        info.max_debt = helpers.parseBalanceValue(balance);
    } else if (helpers.extractBetween(html, "balance-real-maxdebt\">", "<")) |balance| {
        info.max_debt = helpers.parseBalanceValue(balance);
    }

    return info;
}

/// Parse market players from feed page (card-market_unified section)
pub fn parseFeedMarket(allocator: std.mem.Allocator, html: []const u8) ![]MarketPlayer {
    var players: std.ArrayList(MarketPlayer) = .{};

    const market_start = std.mem.indexOf(u8, html, "card-market_unified") orelse return players.items;
    const market_end = std.mem.indexOfPos(u8, html, market_start, "</ul>") orelse html.len;
    const market_section = html[market_start..market_end];

    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, market_section, pos, "player-row")) |row_start| {
        const next_row = std.mem.indexOfPos(u8, market_section, row_start + 10, "player-row") orelse market_section.len;
        const player_html = market_section[row_start..next_row];

        const player = parseFeedMarketPlayer(allocator, player_html) catch {
            pos = row_start + 10;
            continue;
        };

        try players.append(allocator, player);
        pos = next_row;
    }

    return try players.toOwnedSlice(allocator);
}

fn parseFeedMarketPlayer(allocator: std.mem.Allocator, player_html: []const u8) !MarketPlayer {
    const player_id = helpers.extractBetween(player_html, "data-id_player=\"", "\"") orelse return ScraperError.ParseError;

    var position_str: []const u8 = "4";
    if (std.mem.indexOf(u8, player_html, "player-position")) |pos_start| {
        const pos_section = player_html[pos_start..@min(pos_start + 100, player_html.len)];
        position_str = helpers.extractBetween(pos_section, "data-position='", "'") orelse
            helpers.extractBetween(pos_section, "data-position=\"", "\"") orelse "4";
    }
    const position = Position.fromString(position_str) orelse .forward;

    var team_img: []const u8 = "";
    if (std.mem.indexOf(u8, player_html, "team-logo")) |tl_start| {
        const tl_section = player_html[tl_start..@min(tl_start + 200, player_html.len)];
        team_img = helpers.extractBetween(tl_section, "src='", "'") orelse
            helpers.extractBetween(tl_section, "src=\"", "\"") orelse "";
    }

    var points: i32 = 0;
    if (helpers.extractBetween(player_html, "class=\"points\">", "</div>")) |pts| {
        points = std.fmt.parseInt(i32, std.mem.trim(u8, pts, " \t\n\r"), 10) catch 0;
    }

    var player_img: []const u8 = "";
    if (std.mem.indexOf(u8, player_html, "player-avatar")) |pa_start| {
        const pa_section = player_html[pa_start..@min(pa_start + 300, player_html.len)];
        player_img = helpers.extractBetween(pa_section, "<img src=\"", "\"") orelse "";
    }

    var name: []const u8 = "";
    if (helpers.extractBetween(player_html, "class=\"name\">", "</div>")) |name_section| {
        var name_clean = name_section;
        if (std.mem.indexOf(u8, name_clean, "</svg>")) |svg_end| {
            name_clean = name_clean[svg_end + 6 ..];
        }
        if (std.mem.indexOf(u8, name_clean, "<")) |tag_start| {
            name_clean = name_clean[0..tag_start];
        }
        name = std.mem.trim(u8, name_clean, " \t\n\r");
    }

    const under_name = helpers.extractBetween(player_html, "class=\"underName\">", "</div>") orelse "";
    const value = helpers.parseEuropeanNumber(under_name);

    var trend: Trend = .neutral;
    if (std.mem.indexOf(u8, under_name, "value-arrow green")) |_| {
        trend = .up;
    } else if (std.mem.indexOf(u8, under_name, "value-arrow red")) |_| {
        trend = .down;
    }

    var avg: f64 = 0.0;
    if (std.mem.indexOf(u8, player_html, "class=\"avg")) |avg_pos| {
        const avg_section = player_html[avg_pos..@min(avg_pos + 80, player_html.len)];
        if (std.mem.indexOf(u8, avg_section, ">")) |gt| {
            if (std.mem.indexOfPos(u8, avg_section, gt, "</div>")) |end| {
                avg = helpers.parseEuropeanDecimal(std.mem.trim(u8, avg_section[gt + 1 .. end], " \t\n\r"));
            }
        }
    }

    var streak: std.ArrayList(i32) = .{};
    if (std.mem.indexOf(u8, player_html, "class=\"streak\">")) |streak_start| {
        const streak_end = std.mem.indexOfPos(u8, player_html, streak_start, "</div>") orelse player_html.len;
        const streak_section = player_html[streak_start..streak_end];
        var streak_pos: usize = 0;
        while (std.mem.indexOfPos(u8, streak_section, streak_pos, "<span class=\"bg--")) |span_start| {
            if (std.mem.indexOfPos(u8, streak_section, span_start, ">")) |gt| {
                if (std.mem.indexOfPos(u8, streak_section, gt, "</span>")) |span_end| {
                    const val_str = std.mem.trim(u8, streak_section[gt + 1 .. span_end], " \t\n\r");
                    if (val_str.len > 0 and val_str[0] != '-') {
                        const streak_val = std.fmt.parseInt(i32, val_str, 10) catch 0;
                        try streak.append(allocator, streak_val);
                    }
                    streak_pos = span_end;
                    continue;
                }
            }
            break;
        }
    }

    var rival_img: []const u8 = "";
    if (std.mem.indexOf(u8, player_html, "class=\"rival\">")) |r_start| {
        const r_section = player_html[r_start..@min(r_start + 200, player_html.len)];
        rival_img = helpers.extractBetween(r_section, "src='", "'") orelse
            helpers.extractBetween(r_section, "src=\"", "\"") orelse "";
    }

    const id_copy = try allocator.dupe(u8, player_id);

    return MarketPlayer{
        .base = .{
            .id = id_copy,
            .name = name,
            .position = position,
            .value = value,
            .average = avg,
            .points = points,
            .streak = try streak.toOwnedSlice(allocator),
            .team_img = team_img,
            .player_img = player_img,
            .rival_img = rival_img,
            .trend = trend,
        },
        .owner = "",
        .asked_price = value,
        .offered_by = config.FREE_AGENT,
        .own = false,
        .my_bid = null,
    };
}

/// Parse standings from /standings HTML page
pub fn parseStandings(allocator: std.mem.Allocator, html: []const u8) !StandingsResult {
    var total_users: std.ArrayList(User) = .{};
    var gameweek_users: std.ArrayList(User) = .{};

    if (std.mem.indexOf(u8, html, "panel panel-total")) |total_start| {
        const total_end = std.mem.indexOfPos(u8, html, total_start, "panel panel-gameweek") orelse html.len;
        const total_html = html[total_start..total_end];
        try parseStandingsUsers(allocator, total_html, &total_users);
    }

    if (std.mem.indexOf(u8, html, "panel panel-gameweek")) |gw_start| {
        const gw_html = html[gw_start..];
        try parseStandingsUsers(allocator, gw_html, &gameweek_users);
    }

    return .{
        .total = try total_users.toOwnedSlice(allocator),
        .gameweek = try gameweek_users.toOwnedSlice(allocator),
    };
}

fn parseStandingsUsers(allocator: std.mem.Allocator, panel_html: []const u8, users: *std.ArrayList(User)) !void {
    var pos: usize = 0;

    while (std.mem.indexOfPos(u8, panel_html, pos, "href=\"users/")) |user_start| {
        const id_start = user_start + 12;
        const id_end = std.mem.indexOfPos(u8, panel_html, id_start, "/") orelse break;
        const user_id = panel_html[id_start..id_end];

        const next_user = std.mem.indexOfPos(u8, panel_html, id_end, "href=\"users/") orelse panel_html.len;
        const user_html = panel_html[user_start..next_user];

        const user = parseStandingsUserHtml(allocator, user_id, user_html) catch {
            pos = id_end;
            continue;
        };

        try users.append(allocator, user);
        pos = next_user;
    }
}

fn parseStandingsUserHtml(allocator: std.mem.Allocator, user_id: []const u8, user_html: []const u8) !User {
    const position_str = helpers.extractBetween(user_html, "class=\"position\">", "</div>") orelse "0";
    const position: i32 = std.fmt.parseInt(i32, std.mem.trim(u8, position_str, " \t\n\r"), 10) catch 0;

    const avatar_section = helpers.extractBetween(user_html, "user-avatar", "</div>") orelse "";
    const user_img = helpers.extractBetween(avatar_section, "src=\"", "\"") orelse "";

    const name_section = helpers.extractBetween(user_html, "class=\"name", "</div>") orelse "";
    const name_start = std.mem.indexOf(u8, name_section, ">") orelse 0;
    const name = std.mem.trim(u8, name_section[name_start + 1 ..], " \t\n\r");

    const played_section = helpers.extractBetween(user_html, "class=\"played\">", "</div>") orelse "";
    const played = std.mem.trim(u8, played_section, " \t\n\r");

    var players_count: ?i32 = null;
    if (std.mem.indexOf(u8, played, "jugadores") != null or std.mem.indexOf(u8, played, "Jugadores") != null) {
        var num_start: ?usize = null;
        for (played, 0..) |c, i| {
            if (c >= '0' and c <= '9') {
                if (num_start == null) num_start = i;
            } else if (num_start != null) {
                const num_str = played[num_start.?..i];
                players_count = std.fmt.parseInt(i32, num_str, 10) catch null;
                break;
            }
        }
    }

    var value: ?i64 = null;
    if (std.mem.indexOf(u8, played, "€")) |euro_pos| {
        value = helpers.parseEuropeanNumber(played[euro_pos..]);
        if (value == 0) value = null;
    }

    const points_section = helpers.extractBetween(user_html, "class=\"points\">", "</div>") orelse "";
    const points_end = std.mem.indexOf(u8, points_section, "<") orelse points_section.len;
    const points_str = std.mem.trim(u8, points_section[0..points_end], " \t\n\r");
    var points: i32 = 0;
    for (points_str) |c| {
        if (c >= '0' and c <= '9') {
            points = points * 10 + @as(i32, c - '0');
        }
    }

    const diff = helpers.extractBetween(user_html, "class=\"diff\">", "</div>") orelse null;
    const diff_trimmed = if (diff) |d| std.mem.trim(u8, d, " \t\n\r") else null;

    const myself = std.mem.indexOf(u8, user_html, "is-me") != null or
        std.mem.indexOf(u8, user_html, "class=\"name is-me\"") != null;

    const id_copy = try allocator.dupe(u8, user_id);

    return User{
        .id = id_copy,
        .position = position,
        .name = name,
        .players_count = players_count,
        .value = value,
        .points = points,
        .diff = diff_trimmed,
        .user_img = if (user_img.len > 0) user_img else "https://mier.info/assets/favicon.svg",
        .played = if (played.len > 0) played else null,
        .myself = myself,
    };
}

/// Parse market players from /market HTML page
pub fn parseMarket(allocator: std.mem.Allocator, html: []const u8) !MarketResult {
    var players: std.ArrayList(MarketPlayer) = .{};

    const list_start = std.mem.indexOf(u8, html, "player-list") orelse return .{
        .market = &[_]MarketPlayer{},
        .info = parseBalanceInfo(html),
    };

    var pos: usize = list_start;
    while (std.mem.indexOfPos(u8, html, pos, "<li data-position=")) |li_start| {
        const next_li = std.mem.indexOfPos(u8, html, li_start + 20, "<li data-position=");
        const ul_end = std.mem.indexOfPos(u8, html, li_start, "</ul>");
        const li_end = if (next_li) |n| (if (ul_end) |u| @min(n, u) else n) else (ul_end orelse html.len);
        const player_html = html[li_start..li_end];

        const player = parseMarketPlayerHtml(allocator, player_html) catch {
            pos = li_start + 20;
            continue;
        };

        try players.append(allocator, player);
        pos = li_end;
    }

    return .{
        .market = try players.toOwnedSlice(allocator),
        .info = parseBalanceInfo(html),
    };
}

fn parseMarketPlayerHtml(allocator: std.mem.Allocator, player_html: []const u8) !MarketPlayer {
    const player_id = helpers.extractBetween(player_html, "data-id_player=\"", "\"") orelse return ScraperError.ParseError;

    const position_str = helpers.extractBetween(player_html, "data-position=\"", "\"") orelse
        helpers.extractBetween(player_html, "data-position='", "'") orelse "4";
    const position = Position.fromString(position_str) orelse .forward;

    const price_attr = helpers.extractBetween(player_html, "data-price=\"", "\"") orelse
        helpers.extractBetween(player_html, "data-price='", "'") orelse "0";
    var asked_price = helpers.parseEuropeanNumber(price_attr);

    var team_img_src: []const u8 = "";
    if (std.mem.indexOf(u8, player_html, "team-logo")) |team_logo_pos| {
        const after_class = player_html[team_logo_pos..@min(team_logo_pos + 300, player_html.len)];
        team_img_src = helpers.extractBetween(after_class, "src='", "'") orelse
            helpers.extractBetween(after_class, "src=\"", "\"") orelse "";
    }

    var points: i32 = 0;
    if (helpers.extractBetween(player_html, "data-points=\"", "\"")) |pts| {
        points = std.fmt.parseInt(i32, pts, 10) catch 0;
    } else if (helpers.extractBetween(player_html, "class=\"points\">", "<")) |pts| {
        points = std.fmt.parseInt(i32, std.mem.trim(u8, pts, " \t\n\r"), 10) catch 0;
    }

    var player_img: []const u8 = "";
    if (std.mem.indexOf(u8, player_html, "player-avatar")) |avatar_pos| {
        const avatar_section = player_html[avatar_pos..@min(avatar_pos + 500, player_html.len)];
        player_img = helpers.extractBetween(avatar_section, "<img src=\"", "\"") orelse
            helpers.extractBetween(avatar_section, "<img src='", "'") orelse "";
    }

    var name: []const u8 = "";
    if (helpers.extractBetween(player_html, "class=\"name\">", "</div>")) |name_section| {
        var name_clean = name_section;
        if (std.mem.indexOf(u8, name_clean, "</svg>")) |svg_end| {
            name_clean = name_clean[svg_end + 6 ..];
        }
        if (std.mem.indexOf(u8, name_clean, "<")) |tag_start| {
            name_clean = name_clean[0..tag_start];
        }
        name = std.mem.trim(u8, name_clean, " \t\n\r");
    }

    const under_name = helpers.extractBetween(player_html, "class=\"underName\">", "</div>") orelse "";
    const value = helpers.parseEuropeanNumber(under_name);

    var trend: Trend = .neutral;
    if (std.mem.indexOf(u8, under_name, "value-arrow green")) |_| {
        trend = .up;
    } else if (std.mem.indexOf(u8, under_name, "value-arrow red")) |_| {
        trend = .down;
    }

    var avg: f64 = 0.0;
    if (std.mem.indexOf(u8, player_html, "class=\"avg")) |avg_pos| {
        const avg_section = player_html[avg_pos..@min(avg_pos + 100, player_html.len)];
        if (std.mem.indexOf(u8, avg_section, ">")) |gt| {
            if (std.mem.indexOfPos(u8, avg_section, gt, "</div>")) |end| {
                avg = helpers.parseEuropeanDecimal(std.mem.trim(u8, avg_section[gt + 1 .. end], " \t\n\r"));
            }
        }
    }

    var streak: std.ArrayList(i32) = .{};
    if (std.mem.indexOf(u8, player_html, "class=\"streak\">")) |streak_start| {
        const streak_end = std.mem.indexOfPos(u8, player_html, streak_start, "</div>") orelse player_html.len;
        const streak_section = player_html[streak_start..streak_end];
        var streak_pos: usize = 0;
        while (std.mem.indexOfPos(u8, streak_section, streak_pos, "<span class=\"bg--")) |span_start| {
            if (std.mem.indexOfPos(u8, streak_section, span_start, ">")) |gt| {
                if (std.mem.indexOfPos(u8, streak_section, gt, "</span>")) |span_end| {
                    const value_str = std.mem.trim(u8, streak_section[gt + 1 .. span_end], " \t\n\r");
                    if (value_str.len > 0 and value_str[0] != '-') {
                        const streak_value = std.fmt.parseInt(i32, value_str, 10) catch 0;
                        try streak.append(allocator, streak_value);
                    }
                    streak_pos = span_end;
                    continue;
                }
            }
            break;
        }
    }

    var rival_img: []const u8 = "";
    if (std.mem.indexOf(u8, player_html, "class=\"rival\">")) |rival_start| {
        const rival_section = player_html[rival_start..@min(rival_start + 300, player_html.len)];
        rival_img = helpers.extractBetween(rival_section, "src='", "'") orelse
            helpers.extractBetween(rival_section, "src=\"", "\"") orelse "";
    }

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

    var owner: []const u8 = "";
    var offered_by: []const u8 = config.FREE_AGENT;
    if (helpers.extractBetween(player_html, "class=\"date\">", "</div>")) |date_section| {
        var owner_end = std.mem.indexOf(u8, date_section, ",") orelse date_section.len;
        if (std.mem.indexOf(u8, date_section, "<")) |tag_start| {
            if (tag_start < owner_end) owner_end = tag_start;
        }
        owner = std.mem.trim(u8, date_section[0..owner_end], " \t\n\r");
        if (owner.len > 0) {
            offered_by = owner;
        }
    }

    if (owner.len == 0 or std.mem.indexOf(u8, player_html, config.FREE_AGENT) != null) {
        offered_by = config.FREE_AGENT;
    }

    if (asked_price == 0) {
        if (std.mem.indexOf(u8, player_html, "btn-bid")) |btn_start| {
            const btn_section = player_html[btn_start..@min(btn_start + 200, player_html.len)];
            if (std.mem.indexOf(u8, btn_section, ">")) |gt| {
                if (std.mem.indexOfPos(u8, btn_section, gt, "</button>")) |btn_end| {
                    asked_price = helpers.parseEuropeanNumber(btn_section[gt + 1 .. btn_end]);
                }
            }
        }
    }
    if (asked_price == 0) asked_price = value;

    var my_bid: ?i64 = null;
    if (std.mem.indexOf(u8, player_html, "btn-green")) |green_start| {
        const green_section = player_html[green_start..@min(green_start + 200, player_html.len)];
        if (std.mem.indexOf(u8, green_section, ">")) |gt| {
            if (std.mem.indexOfPos(u8, green_section, gt, "</button>")) |btn_end| {
                const bid_value = helpers.parseEuropeanNumber(green_section[gt + 1 .. btn_end]);
                if (bid_value > 0) my_bid = bid_value;
            }
        }
    }

    const own = std.mem.indexOf(u8, player_html, "En venta") != null;
    const id_copy = try allocator.dupe(u8, player_id);

    return MarketPlayer{
        .base = .{
            .id = id_copy,
            .name = name,
            .position = position,
            .value = value,
            .average = avg,
            .points = points,
            .streak = try streak.toOwnedSlice(allocator),
            .team_img = team_img_src,
            .player_img = player_img,
            .rival_img = rival_img,
            .trend = trend,
            .status = status,
        },
        .owner = owner,
        .asked_price = asked_price,
        .offered_by = offered_by,
        .own = own,
        .my_bid = my_bid,
    };
}

/// Parse team players from /team HTML page
pub fn parseTeam(allocator: std.mem.Allocator, html: []const u8) !TeamResult {
    var players: std.ArrayList(TeamPlayer) = .{};

    const list_start = std.mem.indexOf(u8, html, "list-team") orelse return .{
        .players = &[_]TeamPlayer{},
        .info = parseBalanceInfo(html),
    };

    var pos: usize = list_start;
    while (std.mem.indexOfPos(u8, html, pos, "id=\"player-")) |player_start| {
        const id_start = player_start + 11;
        const id_end = std.mem.indexOfPos(u8, html, id_start, "\"") orelse break;
        const player_id = html[id_start..id_end];

        const next_player = std.mem.indexOfPos(u8, html, id_end, "id=\"player-") orelse html.len;
        const player_html = html[player_start..next_player];

        const player = parseTeamPlayerHtml(allocator, player_id, player_html) catch {
            pos = id_end;
            continue;
        };

        try players.append(allocator, player);
        pos = next_player;
    }

    return .{
        .players = try players.toOwnedSlice(allocator),
        .info = parseBalanceInfo(html),
    };
}

fn parseTeamPlayerHtml(allocator: std.mem.Allocator, player_id: []const u8, player_html: []const u8) !TeamPlayer {
    const team_img = helpers.extractBetween(player_html, "team-logo' width='20' height='20' src='", "'") orelse
        helpers.extractBetween(player_html, "team-logo' width='18' height='18' src='", "'") orelse "";

    const position_str = helpers.extractBetween(player_html, "data-position='", "'") orelse "4";
    const position = Position.fromString(position_str) orelse .forward;

    const points_str = helpers.extractBetween(player_html, "class=\"points\">", "<") orelse "0";
    const points: i32 = std.fmt.parseInt(i32, std.mem.trim(u8, points_str, " \t\n\r"), 10) catch 0;

    const player_img = helpers.extractBetween(player_html, "player-avatar img\" src=\"", "\"") orelse
        helpers.extractBetween(player_html, "player-avatar--md", "loading") orelse "";
    const actual_player_img = if (std.mem.indexOf(u8, player_img, "src=\"")) |src_start|
        helpers.extractBetween(player_img[src_start..], "src=\"", "\"") orelse ""
    else
        player_img;

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

    var name_section = helpers.extractBetween(player_html, "class=\"name\">", "</div>") orelse "";
    if (std.mem.indexOf(u8, name_section, "</svg>")) |svg_end| {
        name_section = name_section[svg_end + 6 ..];
    }
    if (std.mem.indexOf(u8, name_section, "<div class=\"clauses")) |div_start| {
        name_section = name_section[0..div_start];
    }
    const name = std.mem.trim(u8, name_section, " \t\n\r");

    const value_section = helpers.extractBetween(player_html, "<span class=\"euro\">", "</div>") orelse "";
    const value = helpers.parseEuropeanNumber(value_section);

    const has_down_arrow = std.mem.indexOf(u8, player_html, "value-arrow red") != null;
    const has_up_arrow = std.mem.indexOf(u8, player_html, "value-arrow green") != null;
    const trend: Trend = if (has_down_arrow) .down else if (has_up_arrow) .up else .neutral;

    const avg_str = helpers.extractBetween(player_html, "class=\"avg", "</div>") orelse "";
    const avg_value = helpers.extractBetween(avg_str, ">", "<") orelse "0";
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

    var streak: std.ArrayList(i32) = .{};
    var streak_pos: usize = 0;
    while (std.mem.indexOfPos(u8, player_html, streak_pos, "class=\"bg--")) |streak_start| {
        const streak_value_start = std.mem.indexOfPos(u8, player_html, streak_start, ">") orelse break;
        const streak_value_end = std.mem.indexOfPos(u8, player_html, streak_value_start, "</span>") orelse break;
        const streak_value_str = std.mem.trim(u8, player_html[streak_value_start + 1 .. streak_value_end], " \t\n\r");
        const streak_value = std.fmt.parseInt(i32, streak_value_str, 10) catch 0;
        try streak.append(allocator, streak_value);
        streak_pos = streak_value_end;
    }

    const rival_img = helpers.extractBetween(player_html, "class=\"rival\"", "</div>") orelse "";
    const rival_team_img = helpers.extractBetween(rival_img, "src='", "'") orelse "";

    const being_sold = std.mem.indexOf(u8, player_html, "btn-sale") != null and
        std.mem.indexOf(u8, player_html, "En venta") != null;

    const selected = std.mem.indexOf(u8, player_html, "selected") != null;
    const id_copy = try allocator.dupe(u8, player_id);

    return TeamPlayer{
        .base = .{
            .id = id_copy,
            .name = name,
            .position = position,
            .value = value,
            .average = avg,
            .points = points,
            .streak = try streak.toOwnedSlice(allocator),
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
