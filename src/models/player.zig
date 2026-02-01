const std = @import("std");
const config = @import("../config.zig");
const Position = @import("position.zig").Position;
const Status = @import("status.zig").Status;
const Trend = @import("trend.zig").Trend;

/// Value change over a time period
pub const ValueChange = struct {
    timespan: Timespan,
    value: i64,
    change: i64,

    pub const Timespan = enum {
        day,
        week,
        month,
        year,

        pub fn fromSpanish(str: []const u8) ?Timespan {
            if (std.mem.indexOf(u8, str, "día") != null) return .day;
            if (std.mem.indexOf(u8, str, "semana") != null) return .week;
            if (std.mem.indexOf(u8, str, "mes") != null) return .month;
            if (std.mem.indexOf(u8, str, "año") != null) return .year;
            return null;
        }
    };
};

/// Previous owner record
pub const OwnerRecord = struct {
    date: []const u8,
    from: []const u8,
    to: []const u8,
    price: i64,
    transfer_type: []const u8,
};

/// Market rank for different time periods
pub const MarketRanks = struct {
    day: ?i32 = null,
    week: ?i32 = null,
    month: ?i32 = null,
};

/// Base Player struct with all common attributes
pub const Player = struct {
    id: ?[]const u8 = null,
    position: Position = .forward,
    name: []const u8 = "",
    points: i32 = 0,
    value: i64 = 0,
    average: f64 = 0.0,
    trend: Trend = .neutral,
    streak: []const i32 = &[_]i32{},
    status: Status = .none,
    player_img: []const u8 = "",
    team_img: []const u8 = "",
    rival_img: []const u8 = "",
    market_ranks: MarketRanks = .{},
    clause: ?i64 = null,

    // Additional attributes loaded from player details
    values: []const ValueChange = &[_]ValueChange{},
    owners: []const OwnerRecord = &[_]OwnerRecord{},
    goals: ?i32 = null,
    matches: ?i32 = null,
    clauses_rank: ?i32 = null,

    /// Calculate points per million
    pub fn ppm(self: Player) f64 {
        if (self.points == 0 or self.value == 0) return 0;
        return @as(f64, @floatFromInt(self.points)) / @as(f64, @floatFromInt(self.value)) * 1_000_000.0;
    }

    /// Calculate goals per match
    pub fn gpm(self: Player) ?f64 {
        const g = self.goals orelse return null;
        const m = self.matches orelse return null;
        if (m == 0) return null;
        return @as(f64, @floatFromInt(g)) / @as(f64, @floatFromInt(m));
    }

    /// Calculate streak sum
    pub fn streakSum(self: Player) i32 {
        var sum: i32 = 0;
        for (self.streak) |s| {
            sum += s;
        }
        return sum;
    }
};

/// Market player with additional market-specific fields
pub const MarketPlayer = struct {
    base: Player,
    owner: []const u8 = "",
    asked_price: i64 = 0,
    offered_by: []const u8 = config.FREE_AGENT,
    own: bool = false,
    my_bid: ?i64 = null,

    pub fn overprice(self: MarketPlayer) ?f64 {
        if (self.base.value == 0) return null;
        return (@as(f64, @floatFromInt(self.asked_price)) - @as(f64, @floatFromInt(self.base.value))) / @as(f64, @floatFromInt(self.base.value)) * 100.0;
    }

    pub fn isFree(self: MarketPlayer) bool {
        return std.mem.eql(u8, self.offered_by, config.FREE_AGENT);
    }
};

/// Team player with lineup and sale status
pub const TeamPlayer = struct {
    base: Player,
    selected: bool = false,
    being_sold: bool = false,
    own: bool = true,
};

/// Player with offer information
pub const OfferPlayer = struct {
    base: Player,
    best_bid: i64 = 0,
    offered_by: []const u8 = "",
    date: []const u8 = "",

    pub fn difference(self: OfferPlayer) i64 {
        return self.best_bid - self.base.value;
    }

    pub fn differencePercent(self: OfferPlayer) f64 {
        if (self.base.value == 0) return 0;
        return (@as(f64, @floatFromInt(self.best_bid)) / @as(f64, @floatFromInt(self.base.value)) - 1.0) * 100.0;
    }
};

/// Transfer record
pub const TransferPlayer = struct {
    base: Player,
    from: []const u8 = "",
    to: []const u8 = "",
    date: []const u8 = "",
    clause_payment: bool = false,
    other_bids: []const OtherBid = &[_]OtherBid{},

    pub const OtherBid = struct {
        user: []const u8,
        amount: []const u8,
    };

    pub fn isFromMarket(self: TransferPlayer) bool {
        return std.mem.eql(u8, self.from, "Fantasy MARCA");
    }

    pub fn isToMarket(self: TransferPlayer) bool {
        return std.mem.eql(u8, self.to, "Fantasy MARCA");
    }
};

test "player ppm calculation" {
    const player = Player{
        .points = 100,
        .value = 5_000_000,
    };
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), player.ppm(), 0.001);
}

test "market player overprice" {
    var mp = MarketPlayer{
        .base = .{ .value = 1_000_000 },
        .asked_price = 1_200_000,
    };
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), mp.overprice().?, 0.001);
}
