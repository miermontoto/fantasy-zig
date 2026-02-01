const std = @import("std");

pub const Community = struct {
    id: i64,
    name: []const u8 = "",
    code: []const u8 = "",
    id_competition: i64 = 0,
    mode: []const u8 = "",
    direct_transfer: i32 = 0,
    max_debt: i32 = 0,
    community_icon: []const u8 = "",
    id_uc: i64 = 0,
    balance: i64 = 0,
    offers: i32 = 0,
    flag_emoji: []const u8 = "",
    ts_pic: ?i64 = null,
    icon_url: ?[]const u8 = null,
    prize: ?[]const u8 = null,
    updated: ?[]const u8 = null,
    sidebar_visible: ?i32 = null,
    blocked: ?i32 = null,
    mgid: ?[]const u8 = null,
    logo_url: []const u8 = "",
    current: bool = false,

    pub fn isCurrent(self: Community) bool {
        return self.current;
    }
};

pub const CommunitiesData = struct {
    settings_hash: []const u8 = "",
    commit_sha: []const u8 = "",
    communities: []const Community = &[_]Community{},
};
