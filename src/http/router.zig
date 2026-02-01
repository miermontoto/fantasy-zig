const std = @import("std");
const httpz = @import("httpz");
const server = @import("server.zig");

// Import handlers
const health_handler = @import("../handlers/health.zig");
const feed_handler = @import("../handlers/feed.zig");
const market_handler = @import("../handlers/market.zig");
const team_handler = @import("../handlers/team.zig");
const standings_handler = @import("../handlers/standings.zig");
const player_handler = @import("../handlers/player.zig");
const player_gameweek_handler = @import("../handlers/player_gameweek.zig");
const offers_handler = @import("../handlers/offers.zig");
const communities_handler = @import("../handlers/communities.zig");
const top_market_handler = @import("../handlers/top_market.zig");
const auth_handler = @import("../handlers/auth.zig");
const ratings_handler = @import("../handlers/ratings.zig");
const players_list_handler = @import("../handlers/players_list.zig");

pub fn setupRoutes(srv: *httpz.Server(*server.ServerContext)) !void {
    const router = try srv.router(.{});

    // Health check
    router.get("/health", health_handler.handle, .{});

    // API v1 routes
    router.get("/api/v1/feed", feed_handler.handle, .{});
    router.get("/api/v1/market", market_handler.handle, .{});
    router.get("/api/v1/market/top", top_market_handler.handle, .{});
    router.get("/api/v1/team", team_handler.handle, .{});
    router.get("/api/v1/standings", standings_handler.handle, .{});
    router.get("/api/v1/players", players_list_handler.handle, .{});
    router.get("/api/v1/players/:id", player_handler.handle, .{});
    router.get("/api/v1/players/:id/gameweek/:gameweek", player_gameweek_handler.handle, .{});
    router.get("/api/v1/offers", offers_handler.handle, .{});
    router.get("/api/v1/communities", communities_handler.handleList, .{});
    router.post("/api/v1/communities/:id/switch", communities_handler.handleSwitch, .{});
    router.post("/api/v1/auth/xauth", auth_handler.handle, .{});

    // Ratings endpoints
    router.get("/api/v1/ratings/market", ratings_handler.handleMarket, .{});
    router.get("/api/v1/ratings/team", ratings_handler.handleTeam, .{});
    router.get("/api/v1/ratings/player/:id", ratings_handler.handlePlayer, .{});
    router.get("/api/v1/ratings/top", ratings_handler.handleTop, .{});
}
