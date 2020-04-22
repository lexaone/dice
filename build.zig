const std = @import("std");

const builtin = std.builtin;
const debug = std.debug;

const Builder = std.build.Builder;
const CrossTarget = std.zig.CrossTarget;
const LibExeObjStep = std.build.LibExeObjStep;
const Target = std.Target;

const global = @import("src/global.zig");

pub fn build(b: *Builder) void {
    const main_exe = b.addExecutable(global.name, "src/main.zig");

    main_exe.setBuildMode(b.standardReleaseOptions());
    main_exe.force_pic = true;

    main_exe.addPackagePath("clap", "lib/zig-clap/clap.zig");

    main_exe.linkLibC();
    main_exe.linkSystemLibrary("argon2");

    switch (main_exe.build_mode) {
        .ReleaseFast, .ReleaseSmall => main_exe.strip = true,
        else => {},
    }

    //if (main_exe.is_linking_libc) {
    //    var cross_abi = Target.current.abi;
    //    cross_abi = setAbiOptions(main_exe);

    //    if (Target.current.abi != cross_abi)
    //        main_exe.setTarget(CrossTarget.fromTarget(Target{
    //            .cpu = Target.current.cpu,
    //            .os = Target.current.os,
    //            .abi = cross_abi,
    //        }));
    //}

    main_exe.install();
    b.getInstallStep().dependOn(&main_exe.step);
}

fn setAbiOptions(artifact: *LibExeObjStep) Target.Abi {
    return switch (Target.current.os.tag) {
        .linux => block: {
            const use_glibc = artifact.builder.option(bool, "use-glibc", "use glibc as standard c library") orelse false;
            const use_musl = artifact.builder.option(bool, "use-musl", "use musl as standard c library") orelse false;

            if (use_glibc and !use_musl)
                break :block Target.Abi.gnu
            else if (use_musl and !use_glibc)
                break :block Target.Abi.musl
            else if (!use_glibc and !use_musl)
                break :block Target.current.abi
            else {
                debug.warn("Multiple libc modes (of -Duse-glibc and -Duse-musl)", .{});
                artifact.builder.markInvalidUserInput();
                break :block Target.current.abi;
            }
        },
        else => Target.current.abi,
    };
}

fn foo() void {
    const target = std.Target{
        .cpu = builtin.cpu,
        .os = builtin.os,
        //.abi = std.Target.Abi.gnu,
        .abi = std.Target.Abi.musl,
    };

    artifact.setTarget(CrossTarget.fromTarget(target));

    const triple = target.linuxTriple(artifact.builder.allocator);

    artifact.addIncludeDir("/usr/local/include");
    artifact.addIncludeDir("/usr/include");
    artifact.addIncludeDir(artifact.builder.fmt("/usr/include/{}", .{triple}));

    artifact.addLibPath("/usr/lib");
    artifact.addLibPath("/usr/lib64");
    artifact.addLibPath("/lib");
    artifact.addLibPath("/lib64");
    artifact.addLibPath("/usr/local/lib");
    artifact.addLibPath("/usr/local/lib64");
    artifact.addLibPath(artifact.builder.fmt("/usr/lib/{}", .{triple}));
    artifact.addLibPath(artifact.builder.fmt("/lib/{}", .{triple}));
}
