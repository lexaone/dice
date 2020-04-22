const std = @import("std");

const crypto = std.crypto;
const debug = std.debug;
const fmt = std.fmt;
const mem = std.mem;

const c = @import("c.zig");

const global = @import("global.zig");

// Big thank-you to Electronic Frontier Foundation (EFF) for the improved
// wordlist.
//
// https://www.eff.org/deeplinks/2016/07/new-wordlists-random-passphrases
//
// archive page: https://archive.is/1kFCn
// txt file: https://archive.is/gjXfJ
const wordlist = @embedFile("../lib/eff_large_wordlist.txt");

pub const Param = struct {
    user_name: []const u8,
    site_name: []const u8,
    counter: u8,
    word_count: u4,
};

const GeneratePassphraseError = error{
    SaltNotAllocated,
    KeyNotAllocated,
    SeedNotAllocated,
    OutOfMemory,
};

pub fn generatePassword(allocator: *mem.Allocator, param: Param, password: []const u8, output: []u8) GeneratePassphraseError!void {
    const salt = block: {
        const salt_length = 64;

        var salt = [_]u8{0} ** salt_length;
        crypto.Blake3.hash(
            fmt.allocPrint(allocator, "{}{}{}", .{
                global.id,
                global.utf8Length(param.user_name) catch unreachable,
                param.user_name,
            }) catch return error.SaltNotAllocated,
            &salt,
        );
        break :block salt;
    };

    var key = block: {
        const iterations: u32 = 64;
        const memory_usage: u32 = 4096; // 4096 KiB == 4194304 bytes
        const parallelism: u32 = 1;

        // BLAKE3's keyed hash function can only accept an array the size of
        // 32 bytes.
        const key_length = 32;

        var key = [_]u8{0} ** key_length;
        switch (c.argon2id_hash_raw(
            iterations,
            memory_usage,
            parallelism,
            password.ptr,
            password.len,
            &salt,
            salt.len,
            &key,
            key.len,
        )) {
            c.ARGON2_MEMORY_ALLOCATION_ERROR => return error.KeyNotAllocated,
            c.ARGON2_OK => break :block key,
            else => unreachable,
        }
    };

    defer mem.secureZero(u8, &key);

    var seed = block0: {
        const seed_length = 64;

        var seed = [_]u8{0} ** seed_length;
        const input_hash = block1: {
            var input_hash = [_]u8{0} ** seed_length;
            crypto.Blake3.hash(
                fmt.allocPrint(allocator, "{}{}{}{}", .{
                    global.id,
                    global.utf8Length(param.site_name) catch unreachable,
                    param.site_name,
                    param.counter,
                }) catch return error.SeedNotAllocated,
                &input_hash,
            );

            break :block1 input_hash;
        };
        var keyed_hash = crypto.Blake3.init_keyed(key);
        keyed_hash.update(&input_hash);
        keyed_hash.final(&seed);

        break :block0 seed;
    };

    defer mem.secureZero(u8, &seed);

    var istanbul = allocator.alloc(u8, param.word_count) catch return error.OutOfMemory;
    {
        mem.set(u8, istanbul, 5);
        var para: usize = seed.len - istanbul.len * 5;
        var i: usize = 0;

        while (para > 0) : ({
            para -= 1;
            i += 1;
        })
            istanbul[i % istanbul.len] += 1;
    }

    var romania = allocator.alloc([]u8, param.word_count) catch return error.OutOfMemory;
    {
        var para: usize = 0;
        var mexer: usize = 0;

        for (romania) |*roman, index| {
            mexer += istanbul[index % istanbul.len];
            roman.* = seed[para..mexer];
            para = mexer;
        }
    }

    var neverland = allocator.alloc([5]u16, param.word_count) catch return error.OutOfMemory;
    {
        for (neverland) |*never|
            mem.set(u16, &never.*, 1);

        for (romania) |roman, index| {
            var para: usize = roman.len - 5;
            var i: usize = 0;

            while (para > 0) : ({
                para -= 1;
                i += 1;
            })
                neverland[index][i % neverland[index].len] += 1;
        }
    }

    {
        for (neverland) |*never, index| {
            var para: usize = 0;
            var mexer: usize = 0;

            for (never) |*ever| {
                var javier: u16 = 0;
                mexer += ever.*;

                for (romania[index][para..mexer]) |roman|
                    javier += roman;

                ever.* = javier;
                para = mexer;
            }
        }
    }

    {
        const number_of_faces_on_a_traditional_die = 6;

        for (neverland) |*never| {
            for (never) |*ever| {
                ever.* %= number_of_faces_on_a_traditional_die;
                // Change from 0-5 to 1-6.
                ever.* += 1;
                // Turn the number into an ASCII representation of said number.
                ever.* += 0x30;
            }
        }
    }

    {
        var output_indicator: usize = 0;

        for (neverland) |never, index0| {
            var indicator: usize = 0;

            for (never) |ever, index1| {
                while (true) {
                    if (wordlist[indicator] != ever) {
                        while (wordlist[indicator] != '\n') : (indicator += 1) {}
                        indicator += 1 + index1;
                    } else {
                        indicator += 1;
                        break;
                    }
                }
            }

            indicator += 1;

            while (wordlist[indicator] != '\n') : ({
                indicator += 1;
                output_indicator += 1;
            })
                output[output_indicator] = wordlist[indicator];

            // If it's processing the final word, avoid putting the space
            // character at the end of the string array.
            if (index0 == neverland.len - 1) break;

            output[output_indicator] = ' ';
            output_indicator += 1;
        }
    }
}
