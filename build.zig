const std = @import("std");
const build_emsdk = @import("build_emsdk.zig");

const StepType = enum {
    run,
    install_bin,
    install_web,
};
const Step = union(StepType) {
    run: *std.Build.Step.Run,
    install_bin: *std.Build.Step.InstallArtifact,
    install_web: *std.Build.Step.InstallDir,
};

const CompileOptoins = struct {
    name: []const u8,
    root_source_file: []const u8,
};
fn compileInstallRun(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: CompileOptoins,
) !Step {
    if (target.result.isWasm()) {
        if (target.result.os.tag == .emscripten) {
            // wasm32-emscripten
            const lib = b.addStaticLibrary(.{
                .name = opts.name,
                .root_source_file = b.path(opts.root_source_file),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            lib.rdynamic = true;

            const emsdk = b.dependency("emsdk", .{});
            const install = try build_emsdk.emLinkStep(b, emsdk, .{
                .target = target,
                .optimize = optimize,
                .lib_main = lib,
                .use_webgl2 = true,
                .use_emmalloc = true,
                .use_filesystem = true,
                // .shell_file_path = deps.dep_sokol.path("src/sokol/web/shell.html").getPath(b),
                .release_use_closure = false,
                .extra_before = &.{
                    "-sUSE_OFFSET_CONVERTER=1",
                },
            });

            // const install = b.addInstallArtifact(lib, .{});
            b.getInstallStep().dependOn(&install.step);
            // b.installFile("examples/hello.html", "lib/hello.html");
            // b.installFile("examples/hello.js", "lib/hello.js");

            return .{ .install_web = install };
        } else {
            // wasm32-freestanding
            const exe = b.addExecutable(.{
                .name = opts.name,
                .root_source_file = b.path(opts.root_source_file),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            exe.entry = .disabled;
            exe.rdynamic = true;

            const install = b.addInstallArtifact(exe, .{});
            b.getInstallStep().dependOn(&install.step);
            {
                const install_file = b.addInstallFile(
                    b.path("examples/hello.html"),
                    "bin/hello.html",
                );
                install.step.dependOn(&install_file.step);
            }
            {
                const install_file = b.addInstallFile(
                    b.path("examples/hello.js"),
                    "bin/hello.js",
                );
                install.step.dependOn(&install_file.step);
            }

            return .{ .install_bin = install };
        }
    } else {
        const exe = b.addExecutable(.{
            .name = opts.name,
            .root_source_file = b.path(opts.root_source_file),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const install = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install.step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&install.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        return .{ .run = run_cmd };
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const example = CompileOptoins{
        .name = "hello",
        .root_source_file = "examples/hello.zig",
    };

    const result = try compileInstallRun(b, target, optimize, example);

    switch (result) {
        .install_bin => |install| {
            b.step(
                b.fmt("install-{s}", .{example.name}),
                b.fmt("Install the {s} to zig-out/bin", .{example.name}),
            ).dependOn(&install.step);
        },
        .install_web => |install| {
            b.step(
                b.fmt("install-{s}", .{example.name}),
                b.fmt("Install the {s} to zig-out/lib", .{example.name}),
            ).dependOn(&install.step);
        },
        .run => |run| {
            b.step(
                b.fmt("run-{s}", .{example.name}),
                b.fmt("Run the {s}", .{example.name}),
            ).dependOn(&run.step);
        },
    }
}
