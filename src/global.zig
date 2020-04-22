const std = @import("std");

const fmt = std.fmt;
const unicode = std.unicode;

pub const name = "dice";
pub const id = "com.nofmal." ++ name;

pub const major_version = 0;
pub const minor_version = 0;
pub const patch_version = 0;

pub const version_string = block: {
    var buffer: [16]u8 = undefined;
    break :block fmt.bufPrint(&buffer, "{}.{}.{}", .{ major_version, minor_version, patch_version }) catch unreachable;
};

pub fn utf8Length(s: []const u8) !usize {
    const view = try unicode.Utf8View.init(s);
    var iter = view.iterator();
    var length: usize = 0;
    while (iter.nextCodepoint()) |_| length += 1;
    return length;
}
