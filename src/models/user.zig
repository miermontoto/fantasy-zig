const std = @import("std");
const TeamPlayer = @import("player.zig").TeamPlayer;

pub const User = struct {
    id: ?[]const u8 = null,
    position: ?i32 = null,
    name: []const u8 = "",
    players_count: ?i32 = null,
    value: ?i64 = null,
    points: i32 = 0,
    diff: ?[]const u8 = null,
    user_img: []const u8 = "https://mier.info/assets/favicon.svg",
    played: ?[]const u8 = null,
    myself: bool = false,
    average: ?f64 = null,
    bench: []const TeamPlayer = &[_]TeamPlayer{},
};
