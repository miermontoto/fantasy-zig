const std = @import("std");
const Player = @import("../models/player.zig").Player;
const ValueChange = @import("../models/player.zig").ValueChange;

/// Player rating with breakdown of component scores
pub const PlayerRating = struct {
    /// Overall rating from 0-100
    overall: f32,

    /// Individual component scores (0-100 each)
    value_trend: f32,
    participation: f32,
    efficiency: f32,
    performance: f32,
    form: f32,
    clause: f32,

    /// Raw values used for calculation
    raw: RawValues,

    pub const RawValues = struct {
        day_change: i64 = 0,
        week_change: i64 = 0,
        month_change: i64 = 0,
        participation_rate: ?f32 = null,
        ppm: f32 = 0,
        average: f32 = 0,
        streak_sum: i32 = 0,
        clauses_rank: ?i32 = null,
        clause_ratio: ?f32 = null, // clause / value
    };
};

/// Configuration for the rating algorithm
/// This rates players as INVESTMENT opportunities, not raw quality
pub const RatingConfig = struct {
    // Weights for each component (should sum to 1.0)
    // Investment-focused: trend is king, clause opportunity matters
    weight_trend: f32 = 0.35, // Value momentum - THE key investment signal
    weight_clause: f32 = 0.25, // Acquisition opportunity - can you get them?
    weight_participation: f32 = 0.20, // Must play to be worth anything
    weight_form: f32 = 0.10, // Recent performance trajectory
    weight_efficiency: f32 = 0.10, // PPM - reduced weight, expensive stars still valuable

    // Value change ranges (per period)
    max_day_change: i64 = 400_000,
    max_week_change: i64 = 1_500_000,
    max_month_change: i64 = 5_000_000,

    // PPM range - efficiency metric (with floor for expensive players)
    min_ppm: f32 = 1.5, // Lower floor
    max_ppm: f32 = 12.0, // Adjusted ceiling

    // Streak sum range (last 5 games)
    min_streak: f32 = 0.0,
    max_streak: f32 = 40.0,

    // Clause rank range (1 = best bargain, ~500 = most expensive)
    max_clauses_rank: i32 = 500,

    // Minimum participation to be considered
    min_starter_participation: f32 = 70.0,
};

pub const RatingService = struct {
    config: RatingConfig,

    const Self = @This();

    pub fn init(config: ?RatingConfig) Self {
        return Self{
            .config = config orelse RatingConfig{},
        };
    }

    /// Calculate rating for a player using detailed stats
    pub fn calculateRating(self: *Self, stats: PlayerStats) PlayerRating {
        var raw = PlayerRating.RawValues{};

        // Extract value changes
        for (stats.values) |vc| {
            switch (vc.timespan) {
                .day => raw.day_change = vc.change,
                .week => raw.week_change = vc.change,
                .month => raw.month_change = vc.change,
                else => {},
            }
        }

        raw.participation_rate = stats.participation_rate;
        raw.ppm = stats.ppm;
        raw.average = stats.average;
        raw.streak_sum = stats.streak_sum;
        raw.clauses_rank = stats.clauses_rank;

        // Calculate clause ratio
        if (stats.clause) |clause| {
            if (stats.value > 0) {
                raw.clause_ratio = @as(f32, @floatFromInt(clause)) / @as(f32, @floatFromInt(stats.value));
            }
        }

        // Calculate individual component scores
        const value_trend = self.calcTrendScore(raw.day_change, raw.week_change, raw.month_change);
        const efficiency = self.calcEfficiencyScore(raw.ppm);
        const clause_score = self.calcClauseScore(raw.clauses_rank, raw.clause_ratio);
        const participation = self.calcParticipationScore(raw.participation_rate);
        const form = self.calcFormScore(raw.streak_sum);
        const performance = self.calcPerformanceScore(raw.average);

        // Calculate weighted overall score
        const overall = value_trend * self.config.weight_trend +
            efficiency * self.config.weight_efficiency +
            clause_score * self.config.weight_clause +
            participation * self.config.weight_participation +
            form * self.config.weight_form;

        return PlayerRating{
            .overall = overall,
            .value_trend = value_trend,
            .participation = participation,
            .efficiency = efficiency,
            .performance = performance,
            .form = form,
            .clause = clause_score,
            .raw = raw,
        };
    }

    /// Performance score: based on average points per game
    fn calcPerformanceScore(self: *Self, avg: f32) f32 {
        _ = self;
        if (avg <= 0) return 0;
        // avg 2 = 0, avg 8+ = 100
        const min_avg: f32 = 2.0;
        const max_avg: f32 = 8.0;
        const normalized = (avg - min_avg) / (max_avg - min_avg);
        return std.math.clamp(normalized * 100.0, 0.0, 100.0);
    }

    /// Value trend score: weighted combination of day/week/month changes
    /// Stable or positive = good (70+ baseline), negative = penalty
    fn calcTrendScore(self: *Self, day: i64, week: i64, month: i64) f32 {
        // Calculate individual period scores
        const day_score = self.normalizeTrendChange(day, self.config.max_day_change);
        const week_score = self.normalizeTrendChange(week, self.config.max_week_change);
        const month_score = self.normalizeTrendChange(month, self.config.max_month_change);

        // Weight recent changes more heavily
        return day_score * 0.5 + week_score * 0.3 + month_score * 0.2;
    }

    fn normalizeTrendChange(self: *Self, change: i64, max_change: i64) f32 {
        _ = self;
        const change_f = @as(f32, @floatFromInt(change));
        const max_f = @as(f32, @floatFromInt(max_change));
        const ratio = change_f / max_f;

        if (ratio >= 0) {
            // Positive or stable: 70-100 range
            // 0 change = 70 (stable is good)
            // max positive = 100
            return 70.0 + std.math.clamp(ratio, 0.0, 1.0) * 30.0;
        } else {
            // Negative: 20-70 range
            // Small negative = 60-70
            // Large negative = 20-40
            return 70.0 + std.math.clamp(ratio, -1.0, 0.0) * 50.0;
        }
    }

    /// Participation score: high participation = high score
    fn calcParticipationScore(self: *Self, participation: ?f32) f32 {
        const rate = participation orelse return 50.0; // Unknown = neutral

        if (rate >= 90.0) return 100.0; // Regular starter
        if (rate >= self.config.min_starter_participation) {
            // Scale 70-90 to 70-100
            return 70.0 + (rate - 70.0) * 1.5;
        }
        // Below 70%: penalize heavily
        // 0% = 0, 70% = 70
        return rate;
    }

    /// Efficiency score: points per million (PPM)
    /// Higher PPM = better value for money = better investment
    /// Floor at 30 - even expensive stars contribute some efficiency value
    fn calcEfficiencyScore(self: *Self, ppm: f32) f32 {
        if (ppm <= 0) return 30.0; // Floor for any player with points

        // PPM 1.5 = 30 (floor), PPM 12+ = 100
        const range = self.config.max_ppm - self.config.min_ppm;
        const normalized = (ppm - self.config.min_ppm) / range;
        // Map to 30-100 range instead of 0-100
        return 30.0 + std.math.clamp(normalized * 70.0, 0.0, 70.0);
    }

    /// Form score: recent streak performance
    fn calcFormScore(self: *Self, streak_sum: i32) f32 {
        // If no streak data available (0), return optimistic neutral
        // (don't penalize for missing data)
        if (streak_sum == 0) return 60.0;

        const sum_f: f32 = @floatFromInt(streak_sum);
        const range = self.config.max_streak - self.config.min_streak;
        const normalized = (sum_f - self.config.min_streak) / range;
        return std.math.clamp(normalized * 100.0, 0.0, 100.0);
    }

    /// Clause score: measures acquisition opportunity
    /// This is primarily an investment metric - high clause shouldn't tank quality rating
    /// Score range is compressed (40-100) so it doesn't hurt top players too much
    fn calcClauseScore(self: *Self, rank: ?i32, ratio: ?f32) f32 {
        // Clause rank is the primary indicator (80% weight)
        // Lower rank = better clause value relative to peers
        var rank_score: f32 = 60.0; // Neutral if unknown
        if (rank) |r| {
            const rank_f: f32 = @floatFromInt(r);
            const max_f: f32 = @floatFromInt(self.config.max_clauses_rank);
            // Use log scale so differences matter more at low ranks
            // Rank 1 = 100, Rank 500 = ~40 (floor to prevent tanking)
            const normalized = @log10(rank_f + 1) / @log10(max_f + 1);
            rank_score = 100.0 - normalized * 60.0; // Range: 40-100
        }

        // Clause/value ratio (20% weight) - softened impact
        // Even expensive clauses don't hurt the score too badly
        var ratio_score: f32 = 60.0; // Neutral if unknown
        if (ratio) |r| {
            // ratio 1.0-2.0: great deal (90-100)
            // ratio 2.0-4.0: acceptable (60-90)
            // ratio 4.0+: expensive but floor at 40
            if (r <= 2.0) {
                ratio_score = 90.0 + (2.0 - r) * 10.0;
            } else if (r <= 4.0) {
                ratio_score = 90.0 - (r - 2.0) * 15.0;
            } else {
                ratio_score = 60.0 - std.math.clamp((r - 4.0) * 5.0, 0.0, 20.0);
            }
            ratio_score = std.math.clamp(ratio_score, 40.0, 100.0);
        }

        // Weighted combination with a floor to protect quality ratings
        return rank_score * 0.8 + ratio_score * 0.2;
    }
};

/// Input stats needed for rating calculation
pub const PlayerStats = struct {
    // Identity
    id: []const u8 = "",
    name: []const u8 = "",
    position: ?i32 = null,

    // Basic stats
    value: i64 = 0,
    points: i32 = 0,
    average: f32 = 0,
    streak_sum: i32 = 0,

    // Value changes
    values: []const ValueChange = &[_]ValueChange{},

    // Participation
    participation_rate: ?f32 = null,
    matches: ?i32 = null,
    team_games: ?i32 = null,

    // Clause
    clause: ?i64 = null,
    clauses_rank: ?i32 = null,

    // Computed
    ppm: f32 = 0,

    /// Create PlayerStats from a Player and optional detailed info
    pub fn fromPlayer(player: Player) PlayerStats {
        var stats = PlayerStats{
            .id = player.id orelse "",
            .name = player.name,
            .position = @intFromEnum(player.position),
            .value = player.value,
            .points = player.points,
            .average = @floatCast(player.average),
            .streak_sum = player.streakSum(),
            .values = player.values,
            .matches = player.matches,
            .clause = player.clause,
            .clauses_rank = player.clauses_rank,
        };

        // Calculate PPM
        if (player.value > 0 and player.points > 0) {
            stats.ppm = @as(f32, @floatFromInt(player.points)) / @as(f32, @floatFromInt(player.value)) * 1_000_000.0;
        }

        return stats;
    }

    /// Add detailed stats from player details endpoint
    pub fn withDetails(
        self: PlayerStats,
        participation_rate: ?f32,
        clause: ?i64,
        clauses_rank: ?i32,
        values: []const ValueChange,
    ) PlayerStats {
        var updated = self;
        updated.participation_rate = participation_rate;
        if (clause) |c| updated.clause = c;
        if (clauses_rank) |r| updated.clauses_rank = r;
        if (values.len > 0) updated.values = values;
        return updated;
    }
};

/// Rating tier classification
pub const RatingTier = enum {
    elite, // 90+
    excellent, // 80-89
    good, // 70-79
    average, // 55-69
    below_average, // 40-54
    poor, // <40

    pub fn fromScore(score: f32) RatingTier {
        if (score >= 90) return .elite;
        if (score >= 80) return .excellent;
        if (score >= 70) return .good;
        if (score >= 55) return .average;
        if (score >= 40) return .below_average;
        return .poor;
    }

    pub fn toString(self: RatingTier) []const u8 {
        return switch (self) {
            .elite => "Elite",
            .excellent => "Excellent",
            .good => "Good",
            .average => "Average",
            .below_average => "Below Average",
            .poor => "Poor",
        };
    }
};

test "investment rating - good value player" {
    var service = RatingService.init(null);

    // Test a good VALUE player - rising value, good PPM, low clause
    const stats = PlayerStats{
        .value = 8_000_000,
        .points = 120,
        .average = 6.0,
        .streak_sum = 28,
        .participation_rate = 85.0,
        .clauses_rank = 30, // Low rank = cheap clause = great investment
        .clause = 12_000_000, // Reasonable clause
        .ppm = 15.0, // Excellent efficiency
    };

    const rating = service.calculateRating(stats);

    // High investment rating for undervalued player
    try std.testing.expect(rating.overall >= 70);
    try std.testing.expect(rating.efficiency >= 90); // Great PPM
    try std.testing.expect(rating.clause >= 70); // Easy to acquire (rank 30 de 500)
}

test "investment rating - expensive star" {
    var service = RatingService.init(null);

    // Test expensive star - poor investment despite quality
    // Mbappé-like: great player but expensive, high clause, low PPM
    const stats = PlayerStats{
        .value = 85_000_000,
        .points = 220,
        .average = 7.7,
        .streak_sum = 35,
        .participation_rate = 90.0,
        .clauses_rank = 450, // Very high clause rank = expensive
        .clause = 450_000_000,
        .ppm = 2.6, // Low PPM due to high value
    };

    const rating = service.calculateRating(stats);

    // Lower investment rating - expensive to acquire, low efficiency
    try std.testing.expect(rating.efficiency < 45); // Poor PPM (2.6 PPM → ~37)
    // rank 450/500 + ratio 5.3x → ~43 (floor at 40 para no destruir rating de estrellas)
    try std.testing.expect(rating.clause < 50);
}
