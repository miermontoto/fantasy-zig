const std = @import("std");
const config = @import("../config.zig");
const TokenService = @import("token.zig").TokenService;

pub const BrowserError = error{
    ConnectionFailed,
    RequestFailed,
    InvalidResponse,
    NoRefreshToken,
    OutOfMemory,
    Unexpected,
};

pub const Browser = struct {
    allocator: std.mem.Allocator,
    token_service: *TokenService,
    current_community_id: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, token_service: *TokenService) Self {
        return Self{
            .allocator = allocator,
            .token_service = token_service,
            .current_community_id = token_service.getCurrentCommunity(),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Nothing to deinit when using curl
    }

    /// Make a GET request to a path
    pub fn get(self: *Self, path: []const u8) ![]const u8 {
        const url = try std.fmt.allocPrint(self.allocator, "https://{s}{s}", .{ config.FANTASY_BASE_URL, path });
        defer self.allocator.free(url);

        return self.curlFetch("GET", url, null);
    }

    /// Make a POST request with form data
    pub fn post(self: *Self, path: []const u8, payload: []const u8) ![]const u8 {
        const url = try std.fmt.allocPrint(self.allocator, "https://{s}{s}", .{ config.FANTASY_BASE_URL, path });
        defer self.allocator.free(url);

        return self.curlFetch("POST", url, payload);
    }

    fn curlFetch(self: *Self, method: []const u8, url: []const u8, payload: ?[]const u8) ![]const u8 {
        // Build curl command arguments
        var args: std.ArrayList([]const u8) = .{};
        defer args.deinit(self.allocator);

        // Track allocated strings so we can free them after curl runs
        var allocated_strings: std.ArrayList([]const u8) = .{};
        defer {
            for (allocated_strings.items) |s| {
                self.allocator.free(s);
            }
            allocated_strings.deinit(self.allocator);
        }

        try args.append(self.allocator, "curl");
        try args.append(self.allocator, "-s"); // Silent
        try args.append(self.allocator, "-X");
        try args.append(self.allocator, method);

        // Headers
        try args.append(self.allocator, "-H");
        try args.append(self.allocator, "Host: fantasy.marca.com");

        try args.append(self.allocator, "-H");
        const user_agent_header = try std.fmt.allocPrint(self.allocator, "User-Agent: {s}", .{config.USER_AGENT});
        try allocated_strings.append(self.allocator, user_agent_header);
        try args.append(self.allocator, user_agent_header);

        try args.append(self.allocator, "-H");
        try args.append(self.allocator, "Content-Type: application/x-www-form-urlencoded; charset=UTF-8");

        try args.append(self.allocator, "-H");
        try args.append(self.allocator, "X-Requested-With: XMLHttpRequest");

        // Cookie with refresh token
        if (self.token_service.getRefreshToken()) |refresh| {
            try args.append(self.allocator, "-H");
            const cookie_header = try std.fmt.allocPrint(self.allocator, "Cookie: refresh-token={s}", .{refresh});
            try allocated_strings.append(self.allocator, cookie_header);
            try args.append(self.allocator, cookie_header);
        }

        // X-Auth for current community
        if (self.current_community_id) |community_id| {
            if (self.token_service.getXAuth(community_id)) |xauth| {
                try args.append(self.allocator, "-H");
                const xauth_header = try std.fmt.allocPrint(self.allocator, "X-Auth: {s}", .{xauth});
                try allocated_strings.append(self.allocator, xauth_header);
                try args.append(self.allocator, xauth_header);
            }
        }

        // POST data
        if (payload) |data| {
            try args.append(self.allocator, "--data");
            try args.append(self.allocator, data);
        } else if (std.mem.eql(u8, method, "POST")) {
            try args.append(self.allocator, "--data");
            try args.append(self.allocator, "");
        }

        try args.append(self.allocator, url);

        // Execute curl
        var child = std.process.Child.init(args.items, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout_file = child.stdout orelse return BrowserError.RequestFailed;
        const stdout = stdout_file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
            return BrowserError.RequestFailed;
        };

        const result = child.wait() catch {
            self.allocator.free(stdout);
            return BrowserError.RequestFailed;
        };

        if (result.Exited != 0) {
            self.allocator.free(stdout);
            return BrowserError.RequestFailed;
        }

        return stdout;
    }

    // Basic endpoint getters (return HTML)
    pub fn feed(self: *Self) ![]const u8 {
        return self.get("/feed");
    }

    pub fn market(self: *Self) ![]const u8 {
        return self.get("/market");
    }

    pub fn team(self: *Self) ![]const u8 {
        return self.get("/team");
    }

    pub fn standings(self: *Self) ![]const u8 {
        return self.get("/standings");
    }

    // AJAX endpoints (return JSON)
    pub fn player(self: *Self, id: []const u8) ![]const u8 {
        const payload = try std.fmt.allocPrint(self.allocator, "post=players&id={s}", .{id});
        defer self.allocator.free(payload);
        return self.post("/ajax/sw/players", payload);
    }

    pub fn offers(self: *Self) ![]const u8 {
        return self.post("/ajax/sw/offers-received", "post=offers-received");
    }

    pub fn communities(self: *Self) ![]const u8 {
        return self.post("/ajax/community-check", "");
    }

    pub fn topMarket(self: *Self, interval: []const u8) ![]const u8 {
        const payload = try std.fmt.allocPrint(self.allocator, "post=market&interval={s}", .{interval});
        defer self.allocator.free(payload);
        return self.post("/ajax/sw/market", payload);
    }

    pub fn topPlayers(self: *Self) ![]const u8 {
        return self.post("/ajax/sw", "post=players&order=0");
    }

    pub fn user(self: *Self, id: []const u8) ![]const u8 {
        const payload = try std.fmt.allocPrint(self.allocator, "post=users&id={s}", .{id});
        defer self.allocator.free(payload);
        return self.post("/ajax/sw/users", payload);
    }

    pub fn teams(self: *Self, id: []const u8) ![]const u8 {
        const payload = try std.fmt.allocPrint(self.allocator, "post=teams&id={s}", .{id});
        defer self.allocator.free(payload);
        return self.post("/ajax/sw/teams", payload);
    }

    pub fn changeCommunity(self: *Self, id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "/action/change?id_community={s}", .{id});
        defer self.allocator.free(path);

        const result = try self.get(path);
        self.allocator.free(result);
        try self.token_service.setCurrentCommunity(id);
        self.current_community_id = id;
    }

    pub fn setupConnection(self: *Self, community_id: ?[]const u8) void {
        self.current_community_id = community_id orelse self.token_service.getCurrentCommunity();
    }
};
