const std = @import("std");

pub const Community = struct {
    id: i64,
    name: []const u8 = "",
    icon: []const u8 = "",
    balance: i64 = 0,
    offers: i32 = 0,
    current: bool = false,

    pub fn isCurrent(self: Community) bool {
        return self.current;
    }
};
