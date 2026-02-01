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
    settings_hash: []const u8 = "",
    commit_sha: []const u8 = "",
    communities: []Community = &[_]Community{},
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
    name: ?[]const u8,
    position: ?i32,
    points: ?i32,
    value: ?i64,
    avg: ?f32,
    starter: ?bool,
    home_avg: ?f32,
    away_avg: ?f32,
    values: []ValueChange,
    owners: []const OwnerRecord,
    goals: ?i32,
    matches: ?i32,
    team_games: ?i32,
    participation_rate: ?f32,
    clauses_rank: ?i32,
    clause: ?i64,
    // Current owner info
    owner_id: ?i64,
    owner_name: ?[]const u8,
    // Streak data (last 5 games points)
    streak: []const i32,
};

pub const PlayerGameweekStats = struct {
    minutes_played: ?i32,
    goals: ?i32,
    assists: ?i32,
    own_goals: ?i32,
    yellow_card: ?i32,
    red_card: ?i32,
    total_shots: ?i32,
    shots_on_target: ?i32,
    key_passes: ?i32,
    big_chances_created: ?i32,
    total_passes: ?i32,
    accurate_passes: ?i32,
    total_long_balls: ?i32,
    accurate_long_balls: ?i32,
    total_clearances: ?i32,
    total_interceptions: ?i32,
    duels_won: ?i32,
    duels_lost: ?i32,
    aerial_won: ?i32,
    aerial_lost: ?i32,
    possession_lost: ?i32,
    touches: ?i32,
    saves: ?i32,
    goals_conceded: ?i32,
    penalty_won: ?i32,
    penalty_conceded: ?i32,
    penalty_missed: ?i32,
    penalty_saved: ?i32,
    expected_assists: ?f32,
};

pub const PlayerGameweekResult = struct {
    id: ?i64,
    name: ?[]const u8,
    position: ?i32,
    gameweek: ?[]const u8,
    minutes_played: ?i32,
    // Match info
    home_team: ?[]const u8,
    away_team: ?[]const u8,
    home_goals: ?i32,
    away_goals: ?i32,
    is_home: bool,
    match_status: ?[]const u8,
    // Points from different providers
    points_fantasy: ?i32,
    points_marca: ?i32,
    points_md: ?i32,
    points_as: ?i32,
    points_mix: ?i32,
    // Detailed stats
    stats: PlayerGameweekStats,
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
            .name = null,
            .position = null,
            .points = null,
            .value = null,
            .avg = null,
            .starter = null,
            .home_avg = null,
            .away_avg = null,
            .values = &[_]ValueChange{},
            .owners = &[_]OwnerRecord{},
            .goals = null,
            .matches = null,
            .team_games = null,
            .participation_rate = null,
            .clauses_rank = null,
            .clause = null,
            .owner_id = null,
            .owner_name = null,
            .streak = &[_]i32{},
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

        // Parse points array to calculate participation
        if (data.object.get("points")) |points_json| {
            if (points_json == .array) {
                var team_games: i32 = 0;
                for (points_json.array.items) |item| {
                    if (item != .object) continue;
                    // Count games where team has played (teamPlayed == true)
                    if (item.object.get("teamPlayed")) |tp| {
                        if (tp == .bool and tp.bool) {
                            team_games += 1;
                        }
                    }
                }
                result.team_games = team_games;

                // Calculate participation rate
                if (result.matches) |matches| {
                    if (team_games > 0) {
                        result.participation_rate = @as(f32, @floatFromInt(matches)) / @as(f32, @floatFromInt(team_games)) * 100.0;
                    }
                }
            }
        }

        // Parse player info
        if (data.object.get("player")) |player_info| {
            if (player_info == .object) {
                if (player_info.object.get("name")) |n| {
                    result.name = if (n == .string) n.string else null;
                }
                if (player_info.object.get("position")) |p| {
                    result.position = if (p == .integer) @intCast(p.integer) else null;
                }
                if (player_info.object.get("points")) |p| {
                    result.points = if (p == .integer) @intCast(p.integer) else null;
                }
                if (player_info.object.get("value")) |v| {
                    result.value = if (v == .integer) v.integer else null;
                }
                if (player_info.object.get("avg")) |a| {
                    result.avg = switch (a) {
                        .integer => |i| @floatFromInt(i),
                        .float => |f| @floatCast(f),
                        else => null,
                    };
                }
                if (player_info.object.get("clausesRanking")) |cr| {
                    result.clauses_rank = if (cr == .integer) @intCast(cr.integer) else null;
                }
                if (player_info.object.get("clause")) |cl| {
                    if (cl == .object) {
                        // clause is an object with .value field
                        if (cl.object.get("value")) |v| {
                            result.clause = if (v == .integer) v.integer else null;
                        }
                    } else if (cl == .integer) {
                        // fallback for direct integer (legacy?)
                        result.clause = cl.integer;
                    }
                }

                // Parse current owner
                if (player_info.object.get("owner")) |owner| {
                    if (owner == .object) {
                        if (owner.object.get("id")) |id| {
                            result.owner_id = if (id == .integer) id.integer else null;
                        }
                        if (owner.object.get("name")) |n| {
                            result.owner_name = if (n == .string) n.string else null;
                        }
                    }
                }

                // Parse streak (last 5 games points)
                if (player_info.object.get("streak")) |streak_arr| {
                    if (streak_arr == .array) {
                        var streak: std.ArrayList(i32) = .{};
                        for (streak_arr.array.items) |s| {
                            if (s == .object) {
                                if (s.object.get("points")) |p| {
                                    if (p == .integer) {
                                        try streak.append(self.allocator, @intCast(p.integer));
                                    }
                                }
                            } else if (s == .integer) {
                                try streak.append(self.allocator, @intCast(s.integer));
                            }
                        }
                        result.streak = try streak.toOwnedSlice(self.allocator);
                    }
                }
            }
        }

        // Parse starter status
        if (data.object.get("starter")) |s| {
            result.starter = if (s == .bool) s.bool else null;
        }

        // Parse home/away performance splits
        if (data.object.get("home")) |home| {
            if (home == .object) {
                var it = home.object.iterator();
                if (it.next()) |entry| {
                    const stats = entry.value_ptr.*;
                    if (stats == .object) {
                        if (stats.object.get("avg")) |a| {
                            result.home_avg = switch (a) {
                                .integer => |i| @floatFromInt(i),
                                .float => |f| @floatCast(f),
                                else => null,
                            };
                        }
                    }
                }
            }
        }

        if (data.object.get("away")) |away| {
            if (away == .object) {
                var it = away.object.iterator();
                if (it.next()) |entry| {
                    const stats = entry.value_ptr.*;
                    if (stats == .object) {
                        if (stats.object.get("avg")) |a| {
                            result.away_avg = switch (a) {
                                .integer => |i| @floatFromInt(i),
                                .float => |f| @floatCast(f),
                                else => null,
                            };
                        }
                    }
                }
            }
        }

        return result;
    }

    /// Parse player gameweek stats from /ajax/player-gameweek response
    pub fn parsePlayerGameweek(self: *Self, json_str: []const u8) !PlayerGameweekResult {
        const data = try self.checkAjaxResponse(json_str);
        if (data != .object) return ScraperError.ParseError;

        var result = PlayerGameweekResult{
            .id = null,
            .name = null,
            .position = null,
            .gameweek = null,
            .minutes_played = null,
            .home_team = null,
            .away_team = null,
            .home_goals = null,
            .away_goals = null,
            .is_home = false,
            .match_status = null,
            .points_fantasy = null,
            .points_marca = null,
            .points_md = null,
            .points_as = null,
            .points_mix = null,
            .stats = .{
                .minutes_played = null,
                .goals = null,
                .assists = null,
                .own_goals = null,
                .yellow_card = null,
                .red_card = null,
                .total_shots = null,
                .shots_on_target = null,
                .key_passes = null,
                .big_chances_created = null,
                .total_passes = null,
                .accurate_passes = null,
                .total_long_balls = null,
                .accurate_long_balls = null,
                .total_clearances = null,
                .total_interceptions = null,
                .duels_won = null,
                .duels_lost = null,
                .aerial_won = null,
                .aerial_lost = null,
                .possession_lost = null,
                .touches = null,
                .saves = null,
                .goals_conceded = null,
                .penalty_won = null,
                .penalty_conceded = null,
                .penalty_missed = null,
                .penalty_saved = null,
                .expected_assists = null,
            },
        };

        // Basic info
        if (data.object.get("id")) |v| result.id = if (v == .integer) v.integer else null;
        if (data.object.get("name")) |v| result.name = if (v == .string) v.string else null;
        if (data.object.get("position")) |v| result.position = if (v == .integer) @intCast(v.integer) else null;
        if (data.object.get("gameweek")) |v| result.gameweek = if (v == .string) v.string else null;

        // Match info
        if (data.object.get("home")) |v| result.home_team = if (v == .string) v.string else null;
        if (data.object.get("away")) |v| result.away_team = if (v == .string) v.string else null;
        if (data.object.get("goals_home")) |v| result.home_goals = if (v == .integer) @intCast(v.integer) else null;
        if (data.object.get("goals_away")) |v| result.away_goals = if (v == .integer) @intCast(v.integer) else null;
        if (data.object.get("status")) |v| result.match_status = if (v == .string) v.string else null;

        // Determine if home team
        if (data.object.get("match_team_id")) |match_team| {
            if (data.object.get("id_home")) |home_id| {
                if (match_team == .integer and home_id == .integer) {
                    result.is_home = match_team.integer == home_id.integer;
                }
            }
        }

        // Points from different providers
        if (data.object.get("points_marca")) |v| result.points_marca = if (v == .integer) @intCast(v.integer) else null;
        if (data.object.get("points_md")) |v| result.points_md = if (v == .integer) @intCast(v.integer) else null;
        if (data.object.get("points_as")) |v| result.points_as = if (v == .integer) @intCast(v.integer) else null;
        if (data.object.get("points_mix")) |v| result.points_mix = if (v == .integer) @intCast(v.integer) else null;
        if (data.object.get("points_marca_stats")) |v| result.points_fantasy = if (v == .integer) @intCast(v.integer) else null;

        // Parse detailed stats from the stats JSON string
        if (data.object.get("stats")) |stats_str| {
            if (stats_str == .string) {
                const stats_parsed = std.json.parseFromSlice(std.json.Value, self.allocator, stats_str.string, .{}) catch null;
                if (stats_parsed) |sp| {
                    const stats = sp.value;
                    if (stats == .object) {
                        if (stats.object.get("minutesPlayed")) |v| {
                            result.stats.minutes_played = if (v == .integer) @intCast(v.integer) else null;
                            result.minutes_played = result.stats.minutes_played;
                        }
                        if (stats.object.get("goalAssist")) |v| result.stats.assists = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("totalShots")) |v| result.stats.total_shots = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("onTargetScoringAttempt")) |v| result.stats.shots_on_target = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("keyPass")) |v| result.stats.key_passes = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("bigChanceCreated")) |v| result.stats.big_chances_created = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("totalPass")) |v| result.stats.total_passes = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("accuratePass")) |v| result.stats.accurate_passes = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("totalLongBalls")) |v| result.stats.total_long_balls = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("accurateLongBalls")) |v| result.stats.accurate_long_balls = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("totalClearance")) |v| result.stats.total_clearances = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("totalInterceptions")) |v| result.stats.total_interceptions = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("wonContest")) |v| result.stats.duels_won = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("duelLost")) |v| result.stats.duels_lost = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("aerialWon")) |v| result.stats.aerial_won = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("aerialLost")) |v| result.stats.aerial_lost = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("possessionLostCtrl")) |v| result.stats.possession_lost = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("touches")) |v| result.stats.touches = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("saves")) |v| result.stats.saves = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("goalsAgainst")) |v| result.stats.goals_conceded = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("penaltyWon")) |v| result.stats.penalty_won = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("penaltyConceded")) |v| result.stats.penalty_conceded = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("penaltyMiss")) |v| result.stats.penalty_missed = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("penaltySave")) |v| result.stats.penalty_saved = if (v == .integer) @intCast(v.integer) else null;
                        if (stats.object.get("expectedAssists")) |v| {
                            result.stats.expected_assists = switch (v) {
                                .float => |f| @floatCast(f),
                                .integer => |i| @floatFromInt(i),
                                else => null,
                            };
                        }
                    }
                }
            }
        }

        // Parse goals/cards from marca_stats_rating_detailed_filtered
        if (data.object.get("marca_stats_rating_detailed_filtered")) |rating_str| {
            if (rating_str == .string) {
                const rating_parsed = std.json.parseFromSlice(std.json.Value, self.allocator, rating_str.string, .{}) catch null;
                if (rating_parsed) |rp| {
                    const rating = rp.value;
                    if (rating == .object) {
                        if (rating.object.get("goals")) |g| {
                            if (g == .object) {
                                if (g.object.get("value")) |v| result.stats.goals = if (v == .integer) @intCast(v.integer) else null;
                            }
                        }
                        if (rating.object.get("ownGoals")) |g| {
                            if (g == .object) {
                                if (g.object.get("value")) |v| result.stats.own_goals = if (v == .integer) @intCast(v.integer) else null;
                            }
                        }
                        if (rating.object.get("yellowCard")) |g| {
                            if (g == .object) {
                                if (g.object.get("value")) |v| result.stats.yellow_card = if (v == .integer) @intCast(v.integer) else null;
                            }
                        }
                        if (rating.object.get("redCard")) |g| {
                            if (g == .object) {
                                if (g.object.get("value")) |v| result.stats.red_card = if (v == .integer) @intCast(v.integer) else null;
                            }
                        }
                    }
                }
            }
        }

        return result;
    }

    /// Player list item from sw/players list response
    pub const PlayersListItem = struct {
        id: []const u8,
        name: []const u8,
        position: i32,
        points: i32,
        value: i64,
        avg: f32,
        team_img: []const u8,
        player_img: []const u8,
        owner_name: ?[]const u8,
        clause: ?i64,
        clauses_rank: ?i32,
        streak: []const i32,
    };

    pub const PlayersListResult = struct {
        players: []PlayersListItem,
        total: i64,
        offset: i64,
    };

    /// Parse players list from /ajax/sw/players response (with filters)
    pub fn parsePlayersList(self: *Self, json_str: []const u8) !PlayersListResult {
        const data = try self.checkAjaxResponse(json_str);
        if (data != .object) return ScraperError.ParseError;

        var players: std.ArrayList(PlayersListItem) = .{};

        const players_arr = data.object.get("players") orelse return .{
            .players = &[_]PlayersListItem{},
            .total = 0,
            .offset = 0,
        };

        if (players_arr != .array) return .{
            .players = &[_]PlayersListItem{},
            .total = 0,
            .offset = 0,
        };

        for (players_arr.array.items) |item| {
            if (item != .object) continue;

            const id_int = if (item.object.get("id")) |i| (if (i == .integer) i.integer else continue) else continue;
            const id = try std.fmt.allocPrint(self.allocator, "{d}", .{id_int});

            const name = if (item.object.get("name")) |n| (if (n == .string) n.string else "") else "";
            const position = if (item.object.get("position")) |p| (if (p == .integer) @as(i32, @intCast(p.integer)) else 4) else 4;
            const points = if (item.object.get("points")) |p| (if (p == .integer) @as(i32, @intCast(p.integer)) else 0) else 0;
            const value = if (item.object.get("value")) |v| (if (v == .integer) v.integer else 0) else 0;
            const avg: f32 = if (item.object.get("avg")) |a| switch (a) {
                .float => @floatCast(a.float),
                .integer => @floatFromInt(a.integer),
                else => 0.0,
            } else 0.0;

            const team_img = if (item.object.get("teamLogoUrl")) |t| (if (t == .string) t.string else "") else "";
            const player_img = if (item.object.get("photoUrl")) |p| (if (p == .string) p.string else "") else "";

            // Owner info
            var owner_name: ?[]const u8 = null;
            if (item.object.get("owner")) |owner| {
                if (owner == .object) {
                    if (owner.object.get("name")) |on| {
                        if (on == .string) owner_name = on.string;
                    }
                }
            }

            // Clause info
            var clause: ?i64 = null;
            if (item.object.get("clause")) |cl| {
                if (cl == .object) {
                    if (cl.object.get("value")) |v| {
                        clause = if (v == .integer) v.integer else null;
                    }
                } else if (cl == .integer) {
                    clause = cl.integer;
                }
            }

            const clauses_rank: ?i32 = if (item.object.get("clausesRanking")) |cr|
                (if (cr == .integer) @as(i32, @intCast(cr.integer)) else null)
            else
                null;

            // Parse streak (last games points)
            var streak: std.ArrayList(i32) = .{};
            if (item.object.get("streak")) |streak_arr| {
                if (streak_arr == .array) {
                    for (streak_arr.array.items) |s| {
                        if (s == .object) {
                            if (s.object.get("points")) |p| {
                                if (p == .integer) {
                                    try streak.append(self.allocator, @intCast(p.integer));
                                }
                            }
                        } else if (s == .integer) {
                            try streak.append(self.allocator, @intCast(s.integer));
                        }
                    }
                }
            }

            try players.append(self.allocator, .{
                .id = id,
                .name = name,
                .position = position,
                .points = points,
                .value = value,
                .avg = avg,
                .team_img = team_img,
                .player_img = player_img,
                .owner_name = owner_name,
                .clause = clause,
                .clauses_rank = clauses_rank,
                .streak = try streak.toOwnedSlice(self.allocator),
            });
        }

        const total = if (data.object.get("total")) |t| (if (t == .integer) t.integer else 0) else 0;
        const offset = if (data.object.get("offset")) |o| (if (o == .integer) o.integer else 0) else 0;

        return .{
            .players = try players.toOwnedSlice(self.allocator),
            .total = total,
            .offset = offset,
        };
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

        var result = CommunitiesResult{};

        // Extract settingsHash
        if (data.object.get("settingsHash")) |sh| {
            if (sh == .string) result.settings_hash = sh.string;
        }

        // Extract commitSha
        if (data.object.get("commitSha")) |cs| {
            if (cs == .string) result.commit_sha = cs.string;
        }

        var communities: std.ArrayList(Community) = .{};

        const communities_obj = data.object.get("communities") orelse return result;
        if (communities_obj != .object) return result;

        var it = communities_obj.object.iterator();
        while (it.next()) |entry| {
            const community = entry.value_ptr.*;
            if (community != .object) continue;

            const id = if (community.object.get("id")) |i| (if (i == .integer) i.integer else 0) else 0;
            const name = if (community.object.get("name")) |n| (if (n == .string) n.string else "") else "";
            const code = if (community.object.get("code")) |c| (if (c == .string) c.string else "") else "";
            const id_competition = if (community.object.get("id_competition")) |ic| (if (ic == .integer) ic.integer else 0) else 0;
            const mode = if (community.object.get("mode")) |m| (if (m == .string) m.string else "") else "";
            const direct_transfer = if (community.object.get("direct_transfer")) |dt| (if (dt == .integer) @as(i32, @intCast(dt.integer)) else 0) else 0;
            const max_debt = if (community.object.get("max_debt")) |md| (if (md == .integer) @as(i32, @intCast(md.integer)) else 0) else 0;
            const community_icon = if (community.object.get("community_icon")) |ci| (if (ci == .string) ci.string else "") else "";
            const id_uc = if (community.object.get("id_uc")) |iu| (if (iu == .integer) iu.integer else 0) else 0;
            const balance = if (community.object.get("balance")) |b| (if (b == .integer) b.integer else 0) else 0;
            const offer_count = if (community.object.get("offers")) |o| (if (o == .integer) @as(i32, @intCast(o.integer)) else 0) else 0;
            const flag_emoji = if (community.object.get("flag_emoji")) |fe| (if (fe == .string) fe.string else "") else "";
            const ts_pic: ?i64 = if (community.object.get("ts_pic")) |tp| (if (tp == .integer) tp.integer else null) else null;
            const icon_url: ?[]const u8 = if (community.object.get("icon_url")) |iu| (if (iu == .string) iu.string else null) else null;
            const prize: ?[]const u8 = if (community.object.get("prize")) |p| (if (p == .string) p.string else null) else null;
            const updated: ?[]const u8 = if (community.object.get("updated")) |u| (if (u == .string) u.string else null) else null;
            const sidebar_visible: ?i32 = if (community.object.get("sidebar_visible")) |sv| (if (sv == .integer) @as(i32, @intCast(sv.integer)) else null) else null;
            const blocked: ?i32 = if (community.object.get("blocked")) |bl| (if (bl == .integer) @as(i32, @intCast(bl.integer)) else null) else null;
            const mgid: ?[]const u8 = if (community.object.get("mgid")) |mg| (if (mg == .string) mg.string else null) else null;
            const logo_url = if (community.object.get("logoUrl")) |lu| (if (lu == .string) lu.string else "") else "";

            const is_current = if (self.current_community_id) |cid| (id == cid) else false;

            try communities.append(self.allocator, .{
                .id = id,
                .name = name,
                .code = code,
                .id_competition = id_competition,
                .mode = mode,
                .direct_transfer = direct_transfer,
                .max_debt = max_debt,
                .community_icon = community_icon,
                .id_uc = id_uc,
                .balance = balance,
                .offers = offer_count,
                .flag_emoji = flag_emoji,
                .ts_pic = ts_pic,
                .icon_url = icon_url,
                .prize = prize,
                .updated = updated,
                .sidebar_visible = sidebar_visible,
                .blocked = blocked,
                .mgid = mgid,
                .logo_url = logo_url,
                .current = is_current,
            });
        }

        result.communities = try communities.toOwnedSlice(self.allocator);
        return result;
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

        // Extract community name from feed-top-community .name span
        if (std.mem.indexOf(u8, html, "feed-top-community")) |start| {
            const section = html[start..@min(start + 500, html.len)];
            if (extractBetween(section, "<span>", "</span>")) |name| {
                info.community = std.mem.trim(u8, name, " \t\n\r");
            }
        }

        // Extract balance (handle space before ">")
        if (extractBetween(html, "balance-real-current \">", "<")) |balance| {
            info.balance = std.mem.trim(u8, balance, " \t\n\r");
        } else if (extractBetween(html, "balance-real-current\">", "<")) |balance| {
            info.balance = std.mem.trim(u8, balance, " \t\n\r");
        }

        // Extract credits
        if (extractBetween(html, "credits-count \">", "<")) |credits| {
            info.credits = std.mem.trim(u8, credits, " \t\n\r");
        } else if (extractBetween(html, "credits-count\">", "<")) |credits| {
            info.credits = std.mem.trim(u8, credits, " \t\n\r");
        }

        // Extract gameweek name (may be empty, look for Jornada text elsewhere)
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

        // Extract gameweek status (class may have modifiers like --playing)
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

    /// Parse market players from feed page (card-market_unified section)
    pub fn parseFeedMarket(self: *Self, html: []const u8) ![]MarketPlayer {
        var players: std.ArrayList(MarketPlayer) = .{};

        // Find the card-market_unified section
        const market_start = std.mem.indexOf(u8, html, "card-market_unified") orelse return players.items;
        const market_end = std.mem.indexOfPos(u8, html, market_start, "</ul>") orelse html.len;
        const market_section = html[market_start..market_end];

        // Parse each player-row
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, market_section, pos, "player-row")) |row_start| {
            const next_row = std.mem.indexOfPos(u8, market_section, row_start + 10, "player-row") orelse market_section.len;
            const player_html = market_section[row_start..next_row];

            const player = self.parseFeedMarketPlayer(player_html) catch {
                pos = row_start + 10;
                continue;
            };

            try players.append(self.allocator, player);
            pos = next_row;
        }

        return try players.toOwnedSlice(self.allocator);
    }

    fn parseFeedMarketPlayer(self: *Self, player_html: []const u8) !MarketPlayer {
        // Extract player ID
        const player_id = extractBetween(player_html, "data-id_player=\"", "\"") orelse return ScraperError.ParseError;

        // Extract position from player-position data-position
        var position_str: []const u8 = "4";
        if (std.mem.indexOf(u8, player_html, "player-position")) |pos_start| {
            const pos_section = player_html[pos_start..@min(pos_start + 100, player_html.len)];
            position_str = extractBetween(pos_section, "data-position='", "'") orelse
                extractBetween(pos_section, "data-position=\"", "\"") orelse "4";
        }
        const position = Position.fromString(position_str) orelse .forward;

        // Extract team logo
        var team_img: []const u8 = "";
        if (std.mem.indexOf(u8, player_html, "team-logo")) |tl_start| {
            const tl_section = player_html[tl_start..@min(tl_start + 200, player_html.len)];
            team_img = extractBetween(tl_section, "src='", "'") orelse
                extractBetween(tl_section, "src=\"", "\"") orelse "";
        }

        // Extract points
        var points: i32 = 0;
        if (extractBetween(player_html, "class=\"points\">", "</div>")) |pts| {
            points = std.fmt.parseInt(i32, std.mem.trim(u8, pts, " \t\n\r"), 10) catch 0;
        }

        // Extract player image
        var player_img: []const u8 = "";
        if (std.mem.indexOf(u8, player_html, "player-avatar")) |pa_start| {
            const pa_section = player_html[pa_start..@min(pa_start + 300, player_html.len)];
            player_img = extractBetween(pa_section, "<img src=\"", "\"") orelse "";
        }

        // Extract name (strip SVG)
        var name: []const u8 = "";
        if (extractBetween(player_html, "class=\"name\">", "</div>")) |name_section| {
            var name_clean = name_section;
            if (std.mem.indexOf(u8, name_clean, "</svg>")) |svg_end| {
                name_clean = name_clean[svg_end + 6 ..];
            }
            if (std.mem.indexOf(u8, name_clean, "<")) |tag_start| {
                name_clean = name_clean[0..tag_start];
            }
            name = std.mem.trim(u8, name_clean, " \t\n\r");
        }

        // Extract value
        const under_name = extractBetween(player_html, "class=\"underName\">", "</div>") orelse "";
        const value = parseEuropeanNumber(under_name);

        // Extract trend
        var trend: Trend = .neutral;
        if (std.mem.indexOf(u8, under_name, "value-arrow green")) |_| {
            trend = .up;
        } else if (std.mem.indexOf(u8, under_name, "value-arrow red")) |_| {
            trend = .down;
        }

        // Extract average
        var avg: f64 = 0.0;
        if (std.mem.indexOf(u8, player_html, "class=\"avg")) |avg_pos| {
            const avg_section = player_html[avg_pos..@min(avg_pos + 80, player_html.len)];
            if (std.mem.indexOf(u8, avg_section, ">")) |gt| {
                if (std.mem.indexOfPos(u8, avg_section, gt, "</div>")) |end| {
                    avg = parseEuropeanDecimal(std.mem.trim(u8, avg_section[gt + 1 .. end], " \t\n\r"));
                }
            }
        }

        // Extract streak
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
                            try streak.append(self.allocator, streak_val);
                        }
                        streak_pos = span_end;
                        continue;
                    }
                }
                break;
            }
        }

        // Extract rival
        var rival_img: []const u8 = "";
        if (std.mem.indexOf(u8, player_html, "class=\"rival\">")) |r_start| {
            const r_section = player_html[r_start..@min(r_start + 200, player_html.len)];
            rival_img = extractBetween(r_section, "src='", "'") orelse
                extractBetween(r_section, "src=\"", "\"") orelse "";
        }

        const id_copy = try self.allocator.dupe(u8, player_id);

        return MarketPlayer{
            .base = .{
                .id = id_copy,
                .name = name,
                .position = position,
                .value = value,
                .average = avg,
                .points = points,
                .streak = try streak.toOwnedSlice(self.allocator),
                .team_img = team_img,
                .player_img = player_img,
                .rival_img = rival_img,
                .trend = trend,
            },
            .owner = "",
            .asked_price = value,
            .offered_by = "Libre",
            .own = false,
            .my_bid = null,
        };
    }

    /// Parse balance info from market/team HTML footer
    pub fn parseBalanceInfo(html: []const u8) MarketInfo {
        var info = MarketInfo{
            .current_balance = 0,
            .future_balance = 0,
            .max_debt = 0,
        };

        // Note: class may have trailing space before ">" (e.g., 'balance-real-current ">')
        if (extractBetween(html, "balance-real-current \">", "<")) |balance| {
            info.current_balance = parseBalanceValue(balance);
        } else if (extractBetween(html, "balance-real-current\">", "<")) |balance| {
            info.current_balance = parseBalanceValue(balance);
        }

        if (extractBetween(html, "balance-real-future \">", "<")) |balance| {
            info.future_balance = parseBalanceValue(balance);
        } else if (extractBetween(html, "balance-real-future\">", "<")) |balance| {
            info.future_balance = parseBalanceValue(balance);
        }

        if (extractBetween(html, "balance-real-maxdebt \">", "<")) |balance| {
            info.max_debt = parseBalanceValue(balance);
        } else if (extractBetween(html, "balance-real-maxdebt\">", "<")) |balance| {
            info.max_debt = parseBalanceValue(balance);
        }

        return info;
    }

    /// Parse balance value handling both full (254.958.620) and abbreviated (255,0M) formats
    fn parseBalanceValue(text: []const u8) i64 {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");

        // Check for abbreviated format with M suffix (e.g., "255,0M" = 255,000,000)
        if (std.mem.indexOf(u8, trimmed, "M")) |m_pos| {
            const num_part = trimmed[0..m_pos];
            const multiplier: i64 = 1_000_000;

            // Handle decimal part (e.g., "255,0" -> 255.0 million)
            if (std.mem.indexOf(u8, num_part, ",")) |comma_pos| {
                const int_str = num_part[0..comma_pos];
                const frac_str = num_part[comma_pos + 1 ..];
                const int_part = std.fmt.parseInt(i64, int_str, 10) catch 0;
                const frac_part = std.fmt.parseInt(i64, frac_str, 10) catch 0;
                const frac_len: u6 = @intCast(frac_str.len);
                const frac_divisor: i64 = std.math.pow(i64, 10, frac_len);
                return int_part * multiplier + @divTrunc(frac_part * multiplier, frac_divisor);
            } else {
                const int_part = std.fmt.parseInt(i64, num_part, 10) catch 0;
                return int_part * multiplier;
            }
        }

        // Otherwise use standard European number parsing (254.958.620)
        return parseEuropeanNumber(trimmed);
    }

    /// Parse standings from /standings HTML page
    pub fn parseStandings(self: *Self, html: []const u8) !StandingsResult {
        var total_users: std.ArrayList(User) = .{};
        var gameweek_users: std.ArrayList(User) = .{};

        // Find the total standings panel
        if (std.mem.indexOf(u8, html, "panel panel-total")) |total_start| {
            // Find the end of the total panel (next panel or end)
            const total_end = std.mem.indexOfPos(u8, html, total_start, "panel panel-gameweek") orelse html.len;
            const total_html = html[total_start..total_end];

            // Parse users in total standings
            try self.parseStandingsUsers(total_html, &total_users);
        }

        // Find the gameweek standings panel
        if (std.mem.indexOf(u8, html, "panel panel-gameweek")) |gw_start| {
            const gw_html = html[gw_start..];

            // Parse users in gameweek standings
            try self.parseStandingsUsers(gw_html, &gameweek_users);
        }

        return .{
            .total = try total_users.toOwnedSlice(self.allocator),
            .gameweek = try gameweek_users.toOwnedSlice(self.allocator),
        };
    }

    fn parseStandingsUsers(self: *Self, panel_html: []const u8, users: *std.ArrayList(User)) !void {
        var pos: usize = 0;

        // Each user entry starts with href="users/{id}/{name}"
        while (std.mem.indexOfPos(u8, panel_html, pos, "href=\"users/")) |user_start| {
            // Extract user ID from href
            const id_start = user_start + 12; // len("href=\"users/")
            const id_end = std.mem.indexOfPos(u8, panel_html, id_start, "/") orelse break;
            const user_id = panel_html[id_start..id_end];

            // Find the end of this user's entry (next user or end of list)
            const next_user = std.mem.indexOfPos(u8, panel_html, id_end, "href=\"users/") orelse panel_html.len;
            const user_html = panel_html[user_start..next_user];

            // Parse user data
            const user = self.parseStandingsUserHtml(user_id, user_html) catch {
                pos = id_end;
                continue;
            };

            try users.append(self.allocator, user);
            pos = next_user;
        }
    }

    fn parseStandingsUserHtml(self: *Self, user_id: []const u8, user_html: []const u8) !User {
        // Extract position/rank
        const position_str = extractBetween(user_html, "class=\"position\">", "</div>") orelse "0";
        const position: i32 = std.fmt.parseInt(i32, std.mem.trim(u8, position_str, " \t\n\r"), 10) catch 0;

        // Extract user avatar image
        const avatar_section = extractBetween(user_html, "user-avatar", "</div>") orelse "";
        const user_img = extractBetween(avatar_section, "src=\"", "\"") orelse "";

        // Extract name
        const name_section = extractBetween(user_html, "class=\"name", "</div>") orelse "";
        const name_start = std.mem.indexOf(u8, name_section, ">") orelse 0;
        const name = std.mem.trim(u8, name_section[name_start + 1 ..], " \t\n\r");

        // Extract played info (e.g., "16 jugadores" or "8 / 11 Jugadores")
        const played_section = extractBetween(user_html, "class=\"played\">", "</div>") orelse "";
        const played = std.mem.trim(u8, played_section, " \t\n\r");

        // Extract players count from played section
        var players_count: ?i32 = null;
        if (std.mem.indexOf(u8, played, "jugadores") != null or std.mem.indexOf(u8, played, "Jugadores") != null) {
            // Try to extract the first number
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

        // Extract value from played section (e.g., "€ 483.164.000")
        var value: ?i64 = null;
        if (std.mem.indexOf(u8, played, "€")) |euro_pos| {
            value = parseEuropeanNumber(played[euro_pos..]);
            if (value == 0) value = null;
        }

        // Extract points
        const points_section = extractBetween(user_html, "class=\"points\">", "</div>") orelse "";
        // Points are before the <span> tag
        const points_end = std.mem.indexOf(u8, points_section, "<") orelse points_section.len;
        const points_str = std.mem.trim(u8, points_section[0..points_end], " \t\n\r");
        // Remove dots from number (1.189 -> 1189)
        var points: i32 = 0;
        for (points_str) |c| {
            if (c >= '0' and c <= '9') {
                points = points * 10 + @as(i32, c - '0');
            }
        }

        // Extract diff (e.g., "+268")
        const diff = extractBetween(user_html, "class=\"diff\">", "</div>") orelse null;
        const diff_trimmed = if (diff) |d| std.mem.trim(u8, d, " \t\n\r") else null;

        // Check if this is the current user (me)
        const myself = std.mem.indexOf(u8, user_html, "is-me") != null or
            std.mem.indexOf(u8, user_html, "class=\"name is-me\"") != null;

        // Copy user ID
        const id_copy = try self.allocator.dupe(u8, user_id);

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
    /// HTML structure: <ul class="player-list"><li class="player-X-Y" data-position="N" data-price="M">...</li></ul>
    pub fn parseMarket(self: *Self, html: []const u8) !MarketResult {
        var players: std.ArrayList(MarketPlayer) = .{};

        // Find the player-list section
        const list_start = std.mem.indexOf(u8, html, "player-list") orelse return .{
            .market = &[_]MarketPlayer{},
            .info = parseBalanceInfo(html),
        };

        // Parse each <li data-position=...> entry (player list items)
        var pos: usize = list_start;
        while (std.mem.indexOfPos(u8, html, pos, "<li data-position=")) |li_start| {
            // Find the end of this <li> element (next <li or </ul>)
            const next_li = std.mem.indexOfPos(u8, html, li_start + 20, "<li data-position=");
            const ul_end = std.mem.indexOfPos(u8, html, li_start, "</ul>");
            const li_end = if (next_li) |n| (if (ul_end) |u| @min(n, u) else n) else (ul_end orelse html.len);
            const player_html = html[li_start..li_end];

            // Extract player data
            const player = self.parseMarketPlayerHtml(player_html) catch {
                pos = li_start + 20;
                continue;
            };

            try players.append(self.allocator, player);
            pos = li_end;
        }

        return .{
            .market = try players.toOwnedSlice(self.allocator),
            .info = parseBalanceInfo(html),
        };
    }

    fn parseMarketPlayerHtml(self: *Self, player_html: []const u8) !MarketPlayer {
        // Extract player ID from data-id_player attribute
        const player_id = extractBetween(player_html, "data-id_player=\"", "\"") orelse return ScraperError.ParseError;

        // Extract position from data-position on the <li> element (handles both quote styles)
        const position_str = extractBetween(player_html, "data-position=\"", "\"") orelse
            extractBetween(player_html, "data-position='", "'") orelse "4";
        const position = Position.fromString(position_str) orelse .forward;

        // Extract asked price from data-price on the <li> element
        const price_attr = extractBetween(player_html, "data-price=\"", "\"") orelse
            extractBetween(player_html, "data-price='", "'") orelse "0";
        var asked_price = parseEuropeanNumber(price_attr);

        // Extract team logo from img.team-logo (handles both quote styles)
        var team_img_src: []const u8 = "";
        if (std.mem.indexOf(u8, player_html, "team-logo")) |team_logo_pos| {
            const after_class = player_html[team_logo_pos..@min(team_logo_pos + 300, player_html.len)];
            team_img_src = extractBetween(after_class, "src='", "'") orelse
                extractBetween(after_class, "src=\"", "\"") orelse "";
        }

        // Extract points from data-points or .points element
        var points: i32 = 0;
        if (extractBetween(player_html, "data-points=\"", "\"")) |pts| {
            points = std.fmt.parseInt(i32, pts, 10) catch 0;
        } else if (extractBetween(player_html, "class=\"points\">", "<")) |pts| {
            points = std.fmt.parseInt(i32, std.mem.trim(u8, pts, " \t\n\r"), 10) catch 0;
        }

        // Extract player image from .player-avatar img
        var player_img: []const u8 = "";
        if (std.mem.indexOf(u8, player_html, "player-avatar")) |avatar_pos| {
            const avatar_section = player_html[avatar_pos..@min(avatar_pos + 500, player_html.len)];
            player_img = extractBetween(avatar_section, "<img src=\"", "\"") orelse
                extractBetween(avatar_section, "<img src='", "'") orelse "";
        }

        // Extract name from .name div (strip SVG status icons)
        var name: []const u8 = "";
        if (extractBetween(player_html, "class=\"name\">", "</div>")) |name_section| {
            var name_clean = name_section;
            // Strip leading SVG tag if present (status icons like injury/doubt)
            if (std.mem.indexOf(u8, name_clean, "</svg>")) |svg_end| {
                name_clean = name_clean[svg_end + 6 ..];
            }
            // Strip any trailing elements
            if (std.mem.indexOf(u8, name_clean, "<")) |tag_start| {
                name_clean = name_clean[0..tag_start];
            }
            name = std.mem.trim(u8, name_clean, " \t\n\r");
        }

        // Extract value from .underName (format: € 12.479.000)
        const under_name = extractBetween(player_html, "class=\"underName\">", "</div>") orelse "";
        const value = parseEuropeanNumber(under_name);

        // Extract trend from .value-arrow
        var trend: Trend = .neutral;
        if (std.mem.indexOf(u8, under_name, "value-arrow green")) |_| {
            trend = .up;
        } else if (std.mem.indexOf(u8, under_name, "value-arrow red")) |_| {
            trend = .down;
        }

        // Extract average from .avg (format: "5,0") - class may have modifiers like "avg fg--fair"
        var avg: f64 = 0.0;
        if (std.mem.indexOf(u8, player_html, "class=\"avg")) |avg_pos| {
            const avg_section = player_html[avg_pos..@min(avg_pos + 100, player_html.len)];
            if (std.mem.indexOf(u8, avg_section, ">")) |gt| {
                if (std.mem.indexOfPos(u8, avg_section, gt, "</div>")) |end| {
                    avg = parseEuropeanDecimal(std.mem.trim(u8, avg_section[gt + 1 .. end], " \t\n\r"));
                }
            }
        }

        // Extract streak from .streak span elements (format: <span class="bg--...">value</span>)
        var streak: std.ArrayList(i32) = .{};
        if (std.mem.indexOf(u8, player_html, "class=\"streak\">")) |streak_start| {
            const streak_end = std.mem.indexOfPos(u8, player_html, streak_start, "</div>") orelse player_html.len;
            const streak_section = player_html[streak_start..streak_end];
            var streak_pos: usize = 0;
            // Look for <span class="bg--...">value</span> patterns
            while (std.mem.indexOfPos(u8, streak_section, streak_pos, "<span class=\"bg--")) |span_start| {
                if (std.mem.indexOfPos(u8, streak_section, span_start, ">")) |gt| {
                    if (std.mem.indexOfPos(u8, streak_section, gt, "</span>")) |span_end| {
                        const value_str = std.mem.trim(u8, streak_section[gt + 1 .. span_end], " \t\n\r");
                        // Handle "-" for no score
                        if (value_str.len > 0 and value_str[0] != '-') {
                            const streak_value = std.fmt.parseInt(i32, value_str, 10) catch 0;
                            try streak.append(self.allocator, streak_value);
                        }
                        streak_pos = span_end;
                        continue;
                    }
                }
                break;
            }
        }

        // Extract rival team logo from .rival img
        var rival_img: []const u8 = "";
        if (std.mem.indexOf(u8, player_html, "class=\"rival\">")) |rival_start| {
            const rival_section = player_html[rival_start..@min(rival_start + 300, player_html.len)];
            rival_img = extractBetween(rival_section, "src='", "'") orelse
                extractBetween(rival_section, "src=\"", "\"") orelse "";
        }

        // Extract status from SVG use href (#injury, #doubt, #red, #five)
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

        // Extract owner/offered_by from .date section (format: "Username ,")
        var owner: []const u8 = "";
        var offered_by: []const u8 = "Libre";
        if (extractBetween(player_html, "class=\"date\">", "</div>")) |date_section| {
            // Find end of owner name (comma or tag)
            var owner_end = std.mem.indexOf(u8, date_section, ",") orelse date_section.len;
            if (std.mem.indexOf(u8, date_section, "<")) |tag_start| {
                if (tag_start < owner_end) owner_end = tag_start;
            }
            owner = std.mem.trim(u8, date_section[0..owner_end], " \t\n\r");
            if (owner.len > 0) {
                offered_by = owner;
            }
        }

        // Check if free player (no owner or contains "Libre")
        if (owner.len == 0 or std.mem.indexOf(u8, player_html, "Libre") != null) {
            offered_by = "Libre";
        }

        // Fallback: extract price from button text if data-price was 0
        if (asked_price == 0) {
            if (std.mem.indexOf(u8, player_html, "btn-bid")) |btn_start| {
                const btn_section = player_html[btn_start..@min(btn_start + 200, player_html.len)];
                if (std.mem.indexOf(u8, btn_section, ">")) |gt| {
                    if (std.mem.indexOfPos(u8, btn_section, gt, "</button>")) |btn_end| {
                        asked_price = parseEuropeanNumber(btn_section[gt + 1 .. btn_end]);
                    }
                }
            }
        }
        if (asked_price == 0) asked_price = value;

        // Check for our bid (.btn-green.btn-bid)
        var my_bid: ?i64 = null;
        if (std.mem.indexOf(u8, player_html, "btn-green")) |green_start| {
            const green_section = player_html[green_start..@min(green_start + 200, player_html.len)];
            if (std.mem.indexOf(u8, green_section, ">")) |gt| {
                if (std.mem.indexOfPos(u8, green_section, gt, "</button>")) |btn_end| {
                    const bid_value = parseEuropeanNumber(green_section[gt + 1 .. btn_end]);
                    if (bid_value > 0) my_bid = bid_value;
                }
            }
        }

        // Check if this is our own player (contains "En venta")
        const own = std.mem.indexOf(u8, player_html, "En venta") != null;

        // Allocate and copy the player ID
        const id_copy = try self.allocator.dupe(u8, player_id);

        return MarketPlayer{
            .base = .{
                .id = id_copy,
                .name = name,
                .position = position,
                .value = value,
                .average = avg,
                .points = points,
                .streak = try streak.toOwnedSlice(self.allocator),
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

    /// Parse European decimal format (e.g., "8,5" -> 8.5)
    fn parseEuropeanDecimal(text: []const u8) f64 {
        if (std.mem.indexOf(u8, text, ",")) |comma_pos| {
            const int_part = std.fmt.parseFloat(f64, text[0..comma_pos]) catch 0.0;
            const frac_str = text[comma_pos + 1 ..];
            const frac_part = std.fmt.parseFloat(f64, frac_str) catch 0.0;
            const frac_divisor: f64 = @floatFromInt(std.math.pow(u64, 10, frac_str.len));
            return int_part + frac_part / frac_divisor;
        }
        return std.fmt.parseFloat(f64, text) catch 0.0;
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
