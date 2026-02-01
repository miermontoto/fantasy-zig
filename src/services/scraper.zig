//! scraper service - coordinador principal
//! delega parsing a módulos especializados: json.zig para AJAX, html.zig para páginas HTML

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

// módulos del scraper
const helpers = @import("scraper/helpers.zig");
const types = @import("scraper/types.zig");
const json = @import("scraper/json.zig");
const html = @import("scraper/html.zig");

// re-exportar tipos para compatibilidad con API existente
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

const OwnerRecord = @import("../models/player.zig").OwnerRecord;

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

    // ========== JSON Parsing (delegado a json.zig) ==========

    /// Parse player details from /ajax/sw/players response
    pub fn parsePlayer(self: *Self, json_str: []const u8) !PlayerDetailsResult {
        return json.parsePlayer(self.allocator, json_str);
    }

    /// Parse player gameweek stats from /ajax/player-gameweek response
    pub fn parsePlayerGameweek(self: *Self, json_str: []const u8) !PlayerGameweekResult {
        return json.parsePlayerGameweek(self.allocator, json_str);
    }

    /// Parse players list from /ajax/sw/players response (with filters)
    pub fn parsePlayersList(self: *Self, json_str: []const u8) !PlayersListResult {
        return json.parsePlayersList(self.allocator, json_str);
    }

    /// Parse offers from /ajax/sw/offers-received response
    pub fn parseOffers(self: *Self, json_str: []const u8) !OffersResult {
        return json.parseOffers(self.allocator, json_str);
    }

    /// Parse communities from /ajax/community-check response
    pub fn parseCommunities(self: *Self, json_str: []const u8) !CommunitiesResult {
        return json.parseCommunities(self.allocator, json_str, self.current_community_id);
    }

    /// Parse top market from /ajax/sw/market response
    pub fn parseTopMarket(self: *Self, json_str: []const u8, timespan: []const u8) !TopMarketResult {
        return json.parseTopMarket(self.allocator, json_str, timespan);
    }

    /// Parse user data from /ajax/sw/users response
    pub fn parseUser(self: *Self, json_str: []const u8) !User {
        return json.parseUser(self.allocator, json_str);
    }

    // ========== HTML Parsing (delegado a html.zig) ==========

    /// Parse basic feed info from HTML
    pub fn parseFeedInfo(self: *Self, page_html: []const u8) !FeedInfo {
        _ = self;
        return html.parseFeedInfo(page_html);
    }

    /// Parse market players from feed page (card-market_unified section)
    pub fn parseFeedMarket(self: *Self, page_html: []const u8) ![]MarketPlayer {
        return html.parseFeedMarket(self.allocator, page_html);
    }

    /// Parse balance info from market/team HTML footer
    pub fn parseBalanceInfo(page_html: []const u8) MarketInfo {
        return html.parseBalanceInfo(page_html);
    }

    /// Parse standings from /standings HTML page
    pub fn parseStandings(self: *Self, page_html: []const u8) !StandingsResult {
        return html.parseStandings(self.allocator, page_html);
    }

    /// Parse market players from /market HTML page
    pub fn parseMarket(self: *Self, page_html: []const u8) !MarketResult {
        return html.parseMarket(self.allocator, page_html);
    }

    /// Parse team players from /team HTML page
    pub fn parseTeam(self: *Self, page_html: []const u8) !TeamResult {
        return html.parseTeam(self.allocator, page_html);
    }
};
