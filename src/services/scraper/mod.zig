//! módulo principal del scraper
//! re-exporta tipos, helpers y el struct Scraper principal
//!
//! estructura del módulo:
//! - types.zig: tipos de resultado (FeedResult, MarketResult, etc.)
//! - helpers.zig: funciones de extracción de HTML y parsing de números

const std = @import("std");
const config = @import("../../config.zig");

// re-exportar tipos
pub const types = @import("types.zig");
pub const helpers = @import("helpers.zig");

// tipos principales re-exportados para compatibilidad
pub const ScraperError = types.ScraperError;
pub const FeedResult = types.FeedResult;
pub const FeedInfo = types.FeedInfo;
pub const MarketResult = types.MarketResult;
pub const MarketInfo = types.MarketInfo;
pub const StandingsResult = types.StandingsResult;
pub const TeamResult = types.TeamResult;
pub const OffersResult = types.OffersResult;
pub const CommunitiesResult = types.CommunitiesResult;
pub const TopMarketResult = types.TopMarketResult;
pub const PlayerDetailsResult = types.PlayerDetailsResult;
pub const PlayerGameweekStats = types.PlayerGameweekStats;
pub const PlayerGameweekResult = types.PlayerGameweekResult;
pub const PlayersListItem = types.PlayersListItem;
pub const PlayersListResult = types.PlayersListResult;

// imports para el Scraper
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

/// struct principal del scraper
/// coordina el parsing de respuestas HTML y JSON de Fantasy Marca
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

    // ========== JSON Parsing ==========

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
                    try values.append(self.allocator, .{ .timespan = timespan, .value = value, .change = change });
                }
                result.values = try values.toOwnedSlice(self.allocator);
            }
        }

        // Parse player extra info
        if (data.object.get("player_extra")) |extra| {
            if (extra == .object) {
                if (extra.object.get("goals")) |g| result.goals = if (g == .integer) @intCast(g.integer) else null;
                if (extra.object.get("matches")) |m| result.matches = if (m == .integer) @intCast(m.integer) else null;
            }
        }

        // Parse points for participation
        if (data.object.get("points")) |points_json| {
            if (points_json == .array) {
                var team_games: i32 = 0;
                for (points_json.array.items) |item| {
                    if (item != .object) continue;
                    if (item.object.get("teamPlayed")) |tp| {
                        if (tp == .bool and tp.bool) team_games += 1;
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
                if (player_info.object.get("name")) |n| result.name = if (n == .string) n.string else null;
                if (player_info.object.get("position")) |p| result.position = if (p == .integer) @intCast(p.integer) else null;
                if (player_info.object.get("points")) |p| result.points = if (p == .integer) @intCast(p.integer) else null;
                if (player_info.object.get("value")) |v| result.value = if (v == .integer) v.integer else null;
                if (player_info.object.get("avg")) |a| {
                    result.avg = switch (a) {
                        .integer => |i| @floatFromInt(i),
                        .float => |f| @floatCast(f),
                        else => null,
                    };
                }
                if (player_info.object.get("clausesRanking")) |cr| result.clauses_rank = if (cr == .integer) @intCast(cr.integer) else null;
                if (player_info.object.get("clause")) |cl| {
                    if (cl == .object) {
                        if (cl.object.get("value")) |v| result.clause = if (v == .integer) v.integer else null;
                    } else if (cl == .integer) {
                        result.clause = cl.integer;
                    }
                }

                if (player_info.object.get("owner")) |owner| {
                    if (owner == .object) {
                        if (owner.object.get("id")) |id| result.owner_id = if (id == .integer) id.integer else null;
                        if (owner.object.get("name")) |n| result.owner_name = if (n == .string) n.string else null;
                    }
                }

                if (player_info.object.get("streak")) |streak_arr| {
                    if (streak_arr == .array) {
                        var streak: std.ArrayList(i32) = .{};
                        for (streak_arr.array.items) |s| {
                            if (s == .object) {
                                if (s.object.get("points")) |p| {
                                    if (p == .integer) try streak.append(self.allocator, @intCast(p.integer));
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

        if (data.object.get("starter")) |s| result.starter = if (s == .bool) s.bool else null;

        // Parse home/away splits
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

    // nota: los demás métodos de parsing se mantienen en el archivo original
    // por compatibilidad. esta estructura permite migración gradual.
};
