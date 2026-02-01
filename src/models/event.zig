const std = @import("std");
const TransferPlayer = @import("player.zig").TransferPlayer;

pub const EventType = enum {
    gameweek_start,
    gameweek_end,
    clause_drops,
    transfer,
};

pub const GameweekRanking = struct {
    position: []const u8,
    name: []const u8,
    points: i32,
    profit: []const u8,
    user_img: ?[]const u8,
};

pub const ClauseDropPlayer = struct {
    name: []const u8,
    owner: []const u8,
    team_img: []const u8,
    position: []const u8,
    points: i32,
    old_price: []const u8,
    new_price: []const u8,
    player_img: []const u8,
};

pub const EventData = union(EventType) {
    gameweek_start: struct {
        gameweek: []const u8,
        subtitle: []const u8,
        date: []const u8,
    },
    gameweek_end: struct {
        gameweek: []const u8,
        date: []const u8,
        rankings: []const GameweekRanking,
    },
    clause_drops: struct {
        date: []const u8,
        players: []const ClauseDropPlayer,
    },
    transfer: TransferPlayer,
};

pub const Event = struct {
    event_type: EventType,
    date: i64, // Unix timestamp for sorting
    raw_date: []const u8,
    data: EventData,
};
