//! parsing de respuestas JSON (endpoints AJAX de Fantasy Marca)
//! contiene funciones para parsear datos de /ajax/sw/* y similares

const std = @import("std");
const types = @import("types.zig");
const Player = @import("../../models/player.zig").Player;
const MarketPlayer = @import("../../models/player.zig").MarketPlayer;
const TeamPlayer = @import("../../models/player.zig").TeamPlayer;
const OfferPlayer = @import("../../models/player.zig").OfferPlayer;
const ValueChange = @import("../../models/player.zig").ValueChange;
const OwnerRecord = @import("../../models/player.zig").OwnerRecord;
const Position = @import("../../models/position.zig").Position;
const Status = @import("../../models/status.zig").Status;
const Trend = @import("../../models/trend.zig").Trend;
const User = @import("../../models/user.zig").User;
const Community = @import("../../models/community.zig").Community;

// re-importar tipos del módulo
const ScraperError = types.ScraperError;
const PlayerDetailsResult = types.PlayerDetailsResult;
const PlayerGameweekResult = types.PlayerGameweekResult;
const PlayerGameweekStats = types.PlayerGameweekStats;
const PlayersListItem = types.PlayersListItem;
const PlayersListResult = types.PlayersListResult;
const OffersResult = types.OffersResult;
const CommunitiesResult = types.CommunitiesResult;
const TopMarketResult = types.TopMarketResult;

/// Check AJAX response status and extract data
pub fn checkAjaxResponse(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Value {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch {
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
pub fn parsePlayer(allocator: std.mem.Allocator, json_str: []const u8) !PlayerDetailsResult {
    const data = try checkAjaxResponse(allocator, json_str);
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

                try values.append(allocator, .{
                    .timespan = timespan,
                    .value = value,
                    .change = change,
                });
            }
            result.values = try values.toOwnedSlice(allocator);
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
                if (item.object.get("teamPlayed")) |tp| {
                    if (tp == .bool and tp.bool) {
                        team_games += 1;
                    }
                }
            }
            result.team_games = team_games;

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
                    if (cl.object.get("value")) |v| {
                        result.clause = if (v == .integer) v.integer else null;
                    }
                } else if (cl == .integer) {
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
                                    try streak.append(allocator, @intCast(p.integer));
                                }
                            }
                        } else if (s == .integer) {
                            try streak.append(allocator, @intCast(s.integer));
                        }
                    }
                    result.streak = try streak.toOwnedSlice(allocator);
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
pub fn parsePlayerGameweek(allocator: std.mem.Allocator, json_str: []const u8) !PlayerGameweekResult {
    const data = try checkAjaxResponse(allocator, json_str);
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
            const stats_parsed = std.json.parseFromSlice(std.json.Value, allocator, stats_str.string, .{}) catch null;
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
            const rating_parsed = std.json.parseFromSlice(std.json.Value, allocator, rating_str.string, .{}) catch null;
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

/// Parse players list from /ajax/sw/players response (with filters)
pub fn parsePlayersList(allocator: std.mem.Allocator, json_str: []const u8) !PlayersListResult {
    const data = try checkAjaxResponse(allocator, json_str);
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
        const id = try std.fmt.allocPrint(allocator, "{d}", .{id_int});

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

        // Parse streak
        var streak: std.ArrayList(i32) = .{};
        if (item.object.get("streak")) |streak_arr| {
            if (streak_arr == .array) {
                for (streak_arr.array.items) |s| {
                    if (s == .object) {
                        if (s.object.get("points")) |p| {
                            if (p == .integer) {
                                try streak.append(allocator, @intCast(p.integer));
                            }
                        }
                    } else if (s == .integer) {
                        try streak.append(allocator, @intCast(s.integer));
                    }
                }
            }
        }

        try players.append(allocator, .{
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
            .streak = try streak.toOwnedSlice(allocator),
        });
    }

    const total = if (data.object.get("total")) |t| (if (t == .integer) t.integer else 0) else 0;
    const offset = if (data.object.get("offset")) |o| (if (o == .integer) o.integer else 0) else 0;

    return .{
        .players = try players.toOwnedSlice(allocator),
        .total = total,
        .offset = offset,
    };
}

/// Parse offers from /ajax/sw/offers-received response
pub fn parseOffers(allocator: std.mem.Allocator, json_str: []const u8) !OffersResult {
    const data = try checkAjaxResponse(allocator, json_str);
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
        const position_str = try std.fmt.allocPrint(allocator, "pos-{d}", .{position_val});
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
                                try streak.append(allocator, @intCast(sp.integer));
                            }
                        }
                    }
                }
            }
        }

        try offers.append(allocator, .{
            .base = .{
                .id = id,
                .name = name,
                .position = Position.fromString(position_str) orelse .forward,
                .average = avg,
                .value = value,
                .points = points,
                .streak = try streak.toOwnedSlice(allocator),
                .team_img = team_img,
                .player_img = player_img,
            },
            .best_bid = bid,
            .offered_by = uname,
            .date = date,
        });
    }

    return .{ .offers = try offers.toOwnedSlice(allocator) };
}

/// Parse communities from /ajax/community-check response
pub fn parseCommunities(allocator: std.mem.Allocator, json_str: []const u8, current_community_id: ?i64) !CommunitiesResult {
    const data = try checkAjaxResponse(allocator, json_str);
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

        const is_current = if (current_community_id) |cid| (id == cid) else false;

        try communities.append(allocator, .{
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

    result.communities = try communities.toOwnedSlice(allocator);
    return result;
}

/// Parse top market from /ajax/sw/market response
pub fn parseTopMarket(allocator: std.mem.Allocator, json_str: []const u8, timespan: []const u8) !TopMarketResult {
    const data = try checkAjaxResponse(allocator, json_str);
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
                const player = try parseTopMarketPlayer(allocator, item, timespan, index);
                try positive.append(allocator, player);
                index += 1;
            }
        }
    }

    // Parse negative
    if (players_obj.object.get("negative")) |neg_arr| {
        if (neg_arr == .array) {
            var index: i32 = 1;
            var i: usize = neg_arr.array.items.len;
            while (i > 0) {
                i -= 1;
                const item = neg_arr.array.items[i];
                if (item != .object) continue;
                const player = try parseTopMarketPlayer(allocator, item, timespan, -index);
                try negative.append(allocator, player);
                index += 1;
            }
        }
    }

    return .{
        .positive = try positive.toOwnedSlice(allocator),
        .negative = try negative.toOwnedSlice(allocator),
        .last_value = last_value,
        .last_date = last_date,
        .diff = last_value - prev_value,
    };
}

fn parseTopMarketPlayer(allocator: std.mem.Allocator, item: std.json.Value, timespan: []const u8, rank: i32) !Player {
    _ = timespan;
    if (item != .object) return ScraperError.ParseError;

    const id_int = if (item.object.get("id")) |i| (if (i == .integer) i.integer else 0) else 0;
    const id = try std.fmt.allocPrint(allocator, "{d}", .{id_int});
    const name = if (item.object.get("name")) |n| (if (n == .string) n.string else "") else "";
    const position_val = if (item.object.get("position")) |p| (if (p == .integer) p.integer else 1) else 1;
    const position_str = try std.fmt.allocPrint(allocator, "pos-{d}", .{position_val});
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
pub fn parseUser(allocator: std.mem.Allocator, json_str: []const u8) !User {
    const data = try checkAjaxResponse(allocator, json_str);
    if (data != .object) return ScraperError.ParseError;

    var bench: std.ArrayList(TeamPlayer) = .{};

    // Parse team_now
    if (data.object.get("team_now")) |team| {
        if (team == .array) {
            for (team.array.items) |item| {
                if (item != .object) continue;

                const id_int = if (item.object.get("id")) |i| (if (i == .integer) i.integer else 0) else 0;
                const id = try std.fmt.allocPrint(allocator, "{d}", .{id_int});
                const name = if (item.object.get("name")) |n| (if (n == .string) n.string else "") else "";
                const position_val = if (item.object.get("position")) |p| (if (p == .integer) p.integer else 1) else 1;
                const position_str = try std.fmt.allocPrint(allocator, "pos-{d}", .{position_val});
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
                                        try streak.append(allocator, @intCast(sp.integer));
                                    }
                                }
                            }
                        }
                    }
                }

                try bench.append(allocator, .{
                    .base = .{
                        .id = id,
                        .name = name,
                        .position = Position.fromString(position_str) orelse .forward,
                        .value = value,
                        .average = avg,
                        .points = points,
                        .streak = try streak.toOwnedSlice(allocator),
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
        .bench = try bench.toOwnedSlice(allocator),
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
