//! tipos de resultado para el scraper
//! contiene todas las estructuras de datos devueltas por los métodos de parsing

const std = @import("std");
const Player = @import("../../models/player.zig").Player;
const MarketPlayer = @import("../../models/player.zig").MarketPlayer;
const TeamPlayer = @import("../../models/player.zig").TeamPlayer;
const OfferPlayer = @import("../../models/player.zig").OfferPlayer;
const ValueChange = @import("../../models/player.zig").ValueChange;
const OwnerRecord = @import("../../models/player.zig").OwnerRecord;
const User = @import("../../models/user.zig").User;
const Community = @import("../../models/community.zig").Community;
const Event = @import("../../models/event.zig").Event;

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
    owner_id: ?i64,
    owner_name: ?[]const u8,
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
    home_team: ?[]const u8,
    away_team: ?[]const u8,
    home_goals: ?i32,
    away_goals: ?i32,
    is_home: bool,
    match_status: ?[]const u8,
    points_fantasy: ?i32,
    points_marca: ?i32,
    points_md: ?i32,
    points_as: ?i32,
    points_mix: ?i32,
    stats: PlayerGameweekStats,
};

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
