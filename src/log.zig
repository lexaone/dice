const std = @import("std");

const io = std.io;

const red_foreground = "\x1b[31m";
const yellow_foreground = "\x1b[33m";
const reset_foreground = "\x1b[39m";

const bold = "\x1b[1m";
const reset_all = "\x1b[0m";

const stderr = &io.getStdErr().outStream();

var is_verbose_enabled = false;

pub fn fail(bytes: []const u8) void {
    coloredWrite(red_foreground, "Error: ", bytes);
}
pub fn failf(comptime bytes: []const u8, args: var) void {
    coloredPrint(red_foreground, "Error: ", bytes, args);
}

pub fn setVerbose(enable: bool) void {
    is_verbose_enabled = enable;
}

pub fn verbose(bytes: []const u8) void {
    if (is_verbose_enabled) _ = stderr.write(bytes) catch {};
}

pub fn verbosef(comptime bytes: []const u8, args: var) void {
    if (is_verbose_enabled) stderr.print(bytes, args) catch {};
}

pub fn warn(bytes: []const u8) void {
    coloredWrite(yellow_foreground, "Warning: ", bytes);
}
pub fn warnf(comptime bytes: []const u8, args: var) void {
    coloredPrint(yellow_foreground, "Warning: ", bytes, args);
}

fn coloredPrint(comptime fg_color: []const u8, comptime notice: []const u8, comptime bytes: []const u8, args: var) void {
    _ = stderr.write(fg_color ++ bold ++ notice ++ reset_foreground) catch {};
    stderr.print(bytes, args) catch {};
    _ = stderr.write(reset_all) catch {};
}

fn coloredWrite(comptime fg_color: []const u8, comptime notice: []const u8, bytes: []const u8) void {
    _ = stderr.write(fg_color ++ bold ++ notice ++ reset_foreground) catch {};
    _ = stderr.write(bytes) catch {};
    _ = stderr.write(reset_all) catch {};
}
