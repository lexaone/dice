const std = @import("std");

const Target = std.Target;

const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;
const process = std.process;
const unicode = std.unicode;

const algorithm = @import("algorithm.zig");
const clap = @import("clap");
const global = @import("global.zig");
const log = @import("log.zig");

const default_counter = 0;
const default_word_count = 6;
const max_password_length = 64;
const min_password_length = 4;
const max_word_count = 10;
const min_word_count = 5;

// UTF-8 requires at least four bytes to be able to display any code blocks
// in the farthest, most usable unicode plane.
const max_utf8_bytes = 4;

// Variables that must be cleaned up when the application is terminated
// (including by SIGINT).
var arena: ?heap.ArenaAllocator = null;
var generated_password = [_]u8{0} ** 128;
var user_password = [_]u8{0} ** (max_password_length * max_utf8_bytes);

pub fn main() u8 {
    // From the official documentation:
    //
    // "It is generally recommended to avoid using @errorToInt, as the integer
    // representation of an error is not stable across source code changes."
    const MainError = enum(u8) {
        OK,
        EnvironmentVarsNotFound,
        InvalidArguments,
        TerminalUnobtainable,
        InvalidPassword,
        DicewareNotGenerated,
        Unexpected = 255,
    };

    arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.?.deinit();

    const allocator = &arena.?.allocator;

    // os.getpid, which is used inside the deinitOnSigint function, has only
    // been implemented in linux as of Feb 11, 2020.
    if (Target.current.os.tag == .linux) {
        os.sigaction(
            os.SIGINT,
            &os.Sigaction{
                .sigaction = deinitOnSigint,
                .mask = os.empty_sigset,
                .flags = os.SA_SIGINFO,
            },
            null,
        );
    }

    var site_name: []const u8 = undefined;
    var user_name: []const u8 = undefined;

    // As of the current version of Zig (Feb 7, 2020), only linux termios (for
    // hiding password input) is supported.
    var is_password_read_from_stdin = if (Target.current.os.tag == .linux) false else true;

    const stderr = &io.getStdErr().outStream();
    const stdout = &io.getStdOut().outStream();

    // Acquire environment variables. If they don't exist, assign default
    // values.
    var counter: u8 = block: {
        const counter_env_var = process.getEnvVarOwned(allocator, "DICE_COUNTER") catch |err| {
            switch (err) {
                error.OutOfMemory => log.fail("Failed acquiring environment variable; heap ran out of memory\n"),
                error.InvalidUtf8 => {
                    if (Target.current.os.tag == .windows)
                        log.fail("String contains invalid utf-8 codepoints\n")
                    else
                        unreachable;
                },
                error.EnvironmentVariableNotFound => break :block default_counter,
            }
            return @enumToInt(MainError.EnvironmentVarsNotFound);
        };

        break :block fmt.parseUnsigned(u8, counter_env_var, 10) catch |err| {
            switch (err) {
                error.Overflow => log.warnf("DICE_COUNTER environment variable must range from {} to {}; reverting to default value\n", .{ math.minInt(u8), math.maxInt(u8) }),
                error.InvalidCharacter => log.warn("DICE_COUNTER environment variable contains invalid characters; reverting to default value\n"),
            }
            break :block default_counter;
        };
    };

    var word_count: u4 = block: {
        const word_count_env_var = process.getEnvVarOwned(allocator, "DICE_WORD_COUNT") catch |err| {
            switch (err) {
                error.OutOfMemory => log.fail("Failed acquiring environment variable; heap ran out of memory\n"),
                error.InvalidUtf8 => {
                    if (Target.current.os.tag == .windows)
                        log.fail("String contains invalid utf-8 codepoints\n")
                    else
                        unreachable;
                },
                error.EnvironmentVariableNotFound => break :block default_word_count,
            }
            return @enumToInt(MainError.EnvironmentVarsNotFound);
        };

        const temp_var = fmt.parseUnsigned(u4, word_count_env_var, 10) catch |err| {
            switch (err) {
                error.Overflow => log.warnf("DICE_WORD_COUNT environment variable must range from {} to {}; reverting to default value\n", .{ min_word_count, max_word_count }),
                error.InvalidCharacter => log.warn("DICE_WORD_COUNT environment variable contains invalid characters; reverting to default value\n"),
            }
            break :block default_word_count;
        };

        if (temp_var < min_word_count or temp_var > max_word_count) {
            log.warnf("DICE_WORD_COUNT environment variable must range from {} to {}; reverting to default value\n", .{ min_word_count, max_word_count });
            break :block default_word_count;
        }

        break :block temp_var;
    };

    // Argument parsing.
    {
        const params = comptime [_]clap.Param(u8){
            clap.Param(u8){
                .id = 'c',
                .names = clap.Names{
                    .short = 'c',
                    .long = "counter",
                },
                .takes_value = true,
            },
            clap.Param(u8){
                .id = 'w',
                .names = clap.Names{
                    .short = 'w',
                    .long = "words",
                },
                .takes_value = true,
            },
            clap.Param(u8){
                .id = '|',
                .names = clap.Names{
                    .long = "stdin",
                },
            },
            clap.Param(u8){
                .id = 'v',
                .names = clap.Names{
                    .short = 'v',
                    .long = "verbose",
                },
            },

            // Help and version
            clap.Param(u8){
                .id = 'h',
                .names = clap.Names{
                    .short = 'h',
                    .long = "help",
                },
            },
            clap.Param(u8){
                .id = '#',
                .names = clap.Names{
                    .long = "version",
                },
            },

            // Positional arguments
            clap.Param(u8){
                .id = '@',
                .takes_value = true,
            },
        };

        var iter = clap.args.OsIterator.init(allocator) catch |err| {
            log.failf("Iteration failed ({})\n", .{err});
            return @enumToInt(MainError.InvalidArguments);
        };

        var parser = clap.StreamingClap(u8, clap.args.OsIterator){
            .params = &params,
            .iter = &iter,
        };

        var positional = std.AlignedArrayList([]const u8, null).init(allocator);

        while (parser.next() catch |err| {
            log.failf("Parse iteration failed ({})\n", .{err});
            return @enumToInt(MainError.InvalidArguments);
        }) |arg| {
            switch (arg.param.id) {
                'c' => counter = fmt.parseUnsigned(@TypeOf(counter), arg.value.?, 10) catch |err| {
                    switch (err) {
                        error.Overflow => log.failf("Counter value must range from {} to {}\n", .{ math.minInt(@TypeOf(counter)), math.maxInt(@TypeOf(counter)) }),
                        error.InvalidCharacter => log.fail("Counter value contains invalid characters\n"),
                    }
                    return @enumToInt(MainError.InvalidArguments);
                },
                'w' => {
                    word_count = block: {
                        const temp_var = fmt.parseUnsigned(@TypeOf(word_count), arg.value.?, 10) catch |err| {
                            switch (err) {
                                error.Overflow => log.failf("Word count value must range from {} to {}\n", .{ min_word_count, max_word_count }),
                                error.InvalidCharacter => log.fail("Word count value contains invalid characters\n"),
                            }
                            return @enumToInt(MainError.InvalidArguments);
                        };

                        if (temp_var < min_word_count or temp_var > max_word_count) {
                            log.failf("Word count value must range from {} to {}\n", .{ min_word_count, max_word_count });
                            return @enumToInt(MainError.InvalidArguments);
                        }

                        break :block temp_var;
                    };
                },
                '|' => is_password_read_from_stdin = true,
                'v' => log.setVerbose(true),
                'h' => {
                    printHelp(if (iter.exe_arg) |exe_arg| exe_arg else global.name, stdout);
                    return @enumToInt(MainError.OK);
                },
                '#' => {
                    stdout.print("{} {}\n", .{ global.name, global.version_string }) catch {};
                    _ = stdout.write("Copyright (c) 2020 nofmal\n") catch {};
                    _ = stdout.write("Licensed under the zlib license\n") catch {};
                    return @enumToInt(MainError.OK);
                },
                '@' => positional.append(arg.value.?) catch {
                    log.fail("Failed appending positional arguments; heap ran out of memory\n");
                    return @enumToInt(MainError.InvalidArguments);
                },
                else => unreachable,
            }
        }

        if (positional.items.len < 2) {
            log.fail("Username and sitename are required\n");
            printHelp(if (iter.exe_arg) |exe_arg| exe_arg else global.name, stderr);
            return @enumToInt(MainError.InvalidArguments);
        }

        const pos = positional.toOwnedSlice();

        if (pos[0].len == 0) {
            log.fail("User name must not be empty\n");
            return @enumToInt(MainError.InvalidArguments);
        }

        if (pos[1].len == 0) {
            log.fail("Site name must not be empty\n");
            return @enumToInt(MainError.InvalidArguments);
        }

        if (!unicode.utf8ValidateSlice(pos[0])) {
            log.fail("User name contains illegal codepoints\n");
            return @enumToInt(MainError.InvalidArguments);
        }

        if (!unicode.utf8ValidateSlice(pos[1])) {
            log.fail("Site name contains illegal codepoints\n");
            return @enumToInt(MainError.InvalidArguments);
        }

        user_name = pos[0];
        site_name = pos[1];
    }

    log.verbose("\"user_parameter\": {\n");
    log.verbosef("    \"user_name\": {},\n", .{user_name});
    log.verbosef("    \"site_name\": {},\n", .{site_name});
    log.verbosef("    \"counter\": {},\n", .{counter});
    log.verbosef("    \"word_count\": {},\n", .{word_count});
    log.verbose("},\n");

    var bytes_read: usize = 0;
    defer bytes_read = 0;

    // Input and process password
    {
        const stdin_file = io.getStdIn();
        const stdin_stream = &stdin_file.inStream();

        if (is_password_read_from_stdin) {
            bytes_read = stdin_stream.readAll(&user_password) catch |err| {
                log.failf("Failed to read from standard input ({})\n", .{err});
                return @enumToInt(MainError.InvalidPassword);
            };

            errdefer mem.secureZero(u8, &user_password);
            validatePasswordLength(user_password[0..bytes_read]) catch |err| {
                switch (err) {
                    error.InvalidCodepoints => {
                        log.fail("Password contains illegal codepoints\n");
                        return @enumToInt(MainError.InvalidPassword);
                    },
                    error.PasswordTooShort => {
                        log.failf("Password must be longer than {} letters\n", .{min_password_length});
                        return @enumToInt(MainError.InvalidPassword);
                    },
                    error.PasswordTooLong => {
                        log.failf("Password must be shorter than {} letters\n", .{max_password_length});
                        return @enumToInt(MainError.InvalidPassword);
                    },
                }
            };
        } else {
            const old_terminal = os.tcgetattr(stdin_file.handle) catch |err| {
                log.failf("Failed getting terminal attributes ({})\n", .{err});
                return @enumToInt(MainError.TerminalUnobtainable);
            };
            var new_terminal = old_terminal;

            new_terminal.lflag &= ~@as(u32, os.ECHO);
            new_terminal.lflag |= os.ICANON | os.ISIG;
            new_terminal.iflag |= os.ICRNL;

            os.tcsetattr(stdin_file.handle, os.TCSA.FLUSH, new_terminal) catch unreachable;
            defer os.tcsetattr(stdin_file.handle, os.TCSA.FLUSH, old_terminal) catch unreachable;

            while (true) {
                stderr.print("[{}] password for {}: ", .{ global.name, user_name }) catch {};

                while (true) : (bytes_read += 1) {
                    const byte = stdin_stream.readByte() catch |err| {
                        _ = stderr.write("\n") catch {};
                        log.failf("Failed to read from input ({})\n", .{err});
                        return @enumToInt(MainError.InvalidPassword);
                    };

                    switch (byte) {
                        '\r', '\n' => break,
                        else => {
                            if (bytes_read < user_password.len) {
                                user_password[bytes_read] = byte;
                            } else {
                                _ = stderr.write("\n") catch {};
                                log.fail("Password buffer overflowed\n");
                                return @enumToInt(MainError.InvalidPassword);
                            }
                        },
                    }
                }
                _ = stderr.write("\n") catch {};

                validatePasswordLength(user_password[0..bytes_read]) catch |err| {
                    switch (err) {
                        error.InvalidCodepoints => log.fail("Password contains illegal codepoints; please try again\n"),
                        error.PasswordTooShort => log.failf("Password must be longer than {} letters; please try again\n", .{min_password_length}),
                        error.PasswordTooLong => log.failf("Password must be shorter than {} letters; please try again\n", .{max_password_length}),
                    }
                    mem.set(u8, user_password[0..bytes_read], 0);
                    continue;
                };
                break;
            }
        }

        // End of password processing
    }

    defer mem.secureZero(u8, &user_password);

    algorithm.generatePassword(
        allocator,
        algorithm.Param{
            .user_name = user_name,
            .site_name = site_name,
            .counter = counter,
            .word_count = word_count,
        },
        user_password[0..bytes_read],
        &generated_password,
    ) catch |err| {
        switch (err) {
            error.SaltNotAllocated => log.fail("Heap ran out of memory while generating salt\n"),
            error.KeyNotAllocated => log.fail("Heap ran out of memory while generating key\n"),
            error.SeedNotAllocated => log.fail("Heap ran out of memory while generating seed\n"),
            error.OutOfMemory => log.fail("Failed allocating memory during diceware phase\n"),
        }
        return @enumToInt(MainError.DicewareNotGenerated);
    };

    defer mem.secureZero(u8, &generated_password);

    {
        var i: usize = undefined;

        for (generated_password) |byte, index| {
            if (byte == 0) {
                i = index;
                break;
            }
        }

        _ = stderr.write("your password is: ") catch {};
        stdout.print("{}", .{generated_password[0..i]}) catch {};
        _ = stderr.write("\n") catch {};
    }

    return @enumToInt(MainError.OK);
}

fn deinitOnSigint(signo: i32, info: *os.siginfo_t, context: ?*c_void) callconv(.C) void {
    mem.secureZero(u8, &generated_password);
    mem.secureZero(u8, &user_password);
    if (arena) |allocator| allocator.deinit();

    // After cleaning up, proceed to kill this very program with a SIGINT
    // signal. We do this by resetting the SIGINT sigaction handler to SIG_DFL.
    //
    // Big thank-you to https://www.cons.org/cracauer/sigint.html for the
    // protip.
    os.sigaction(
        os.SIGINT,
        &os.Sigaction{
            .sigaction = os.SIG_DFL,
            .mask = os.empty_sigset,
            .flags = os.SA_SIGINFO,
        },
        null,
    );

    os.kill(os.linux.getpid(), os.SIGINT) catch unreachable;
}

fn printHelp(exe: []const u8, outstream: *fs.File.OutStream) void {
    outstream.print("Usage: {} [options] <username> <sitename>\n", .{exe}) catch {};

    _ = outstream.write("\n") catch {};

    _ = outstream.write("Options:\n") catch {};
    outstream.print("  -c, --counter=VALUE  Set the counter value [default: {}]\n", .{default_counter}) catch {};
    _ = outstream.write("      --stdin          Read password from standard input\n") catch {};
    _ = outstream.write("  -w, --words=VALUE    Set the number of words for the resulting generated password\n") catch {};
    outstream.print("                       The value must range from {} to {} [default: {}]\n", .{ min_word_count, max_word_count, default_word_count }) catch {};
    _ = outstream.write("  -v, --verbose        Print extra information\n") catch {};
    _ = outstream.write("  -h, --help           Display this help and exit immediately\n") catch {};
    _ = outstream.write("      --version        Display version information and exit immediately\n") catch {};
}

const ValidatePasswordError = error{
    InvalidCodepoints,
    PasswordTooShort,
    PasswordTooLong,
};

fn validatePasswordLength(string: []const u8) ValidatePasswordError!void {
    const password_length = global.utf8Length(string) catch
        return error.InvalidCodepoints;

    if (password_length < min_password_length)
        return error.PasswordTooShort
    else if (password_length > max_password_length)
        return error.PasswordTooLong;
}
