const std = @import("std");
const httpz = @import("httpz");
const router_mod = @import("router.zig");
const config = @import("../config.zig");
const TokenService = @import("../services/token.zig").TokenService;
const Browser = @import("../services/browser.zig").Browser;
const Scraper = @import("../services/scraper.zig").Scraper;

pub const ServerContext = struct {
    allocator: std.mem.Allocator,
    token_service: *TokenService,

    pub fn createBrowser(self: *ServerContext) Browser {
        return Browser.init(self.allocator, self.token_service);
    }

    pub fn createScraper(self: *ServerContext) Scraper {
        return Scraper.init(self.allocator, self.token_service.getCurrentCommunityInt());
    }
};

pub fn startServer(allocator: std.mem.Allocator, token_service: *TokenService) !void {
    const cfg = config.Config.init();

    var ctx = ServerContext{
        .allocator = allocator,
        .token_service = token_service,
    };

    var server = try httpz.Server(*ServerContext).init(allocator, .{
        .port = cfg.port,
        .address = cfg.host,
    }, &ctx);
    defer server.deinit();

    // Setup routes
    try router_mod.setupRoutes(&server);

    std.log.info("Fantasy API server starting on {s}:{d}", .{ cfg.host, cfg.port });

    // Start the server (blocking)
    try server.listen();
}
