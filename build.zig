const std = @import("std");
const Builder = std.build.Builder;
const builtin = std.builtin;
const CrossTarget = std.zig.CrossTarget;
const debug = std.debug;
const LibExeObjStep = std.build.LibExeObjStep;
const NativePaths = std.zig.system.NativePaths;
const Target = std.Target;

const global = @import("src/global.zig");

pub fn build(b: *Builder) anyerror!void {
    b.setPreferredReleaseMode(.ReleaseFast);

    const main_exe = b.addExecutable(global.name, "src/main.zig");
    main_exe.setBuildMode(b.standardReleaseOptions());
    main_exe.force_pic = true;
    main_exe.addPackagePath("thirdparty/clap", "lib/zig-clap/clap.zig");
    main_exe.linkLibC();
    main_exe.linkSystemLibrary("argon2");

    if (main_exe.is_linking_libc) {
        switch (Target.current.os.tag) {
            .linux => {
                const use_glibc = b.option(bool, "use-glibc", "use glibc as standard c library (linux only)") orelse false;
                const use_musl = b.option(bool, "use-musl", "use musl as standard c library (linux only)") orelse false;

                const cross_abi = abi: {
                    if (use_glibc and !use_musl)
                        break :abi Target.Abi.gnu
                    else if (use_musl and !use_glibc)
                        break :abi Target.Abi.musl
                    else if (!use_glibc and !use_musl)
                        break :abi Target.current.abi
                    else {
                        debug.warn("Multiple libc modes (of -Duse-glibc and -Duse-musl)", .{});
                        b.invalid_user_input = true;
                        break :abi Target.current.abi;
                    }
                };

                main_exe.setTarget(CrossTarget.fromTarget(Target{
                    .cpu = Target.current.cpu,
                    .os = Target.current.os,
                    .abi = cross_abi,
                }));

                // Workaround for zig 0.6.0 nightly, or else the compiler will complain about
                // "explicit_bzero" being unreferenced.
                var native_paths = try NativePaths.detect(b.allocator);
                defer native_paths.deinit();

                for (native_paths.include_dirs.items) |include_dir|
                    main_exe.addIncludeDir(include_dir);

                for (native_paths.lib_dirs.items) |lib_dir|
                    main_exe.addLibPath(lib_dir);
            },
            else => {},
        }
    }

    switch (main_exe.build_mode) {
        .ReleaseFast, .ReleaseSmall => main_exe.strip = true,
        else => {},
    }

    main_exe.install();
    b.getInstallStep().dependOn(&main_exe.step);
}
