//
// from https://github.com/floooh/sokol-zig/blob/master/build.zig
//
const std = @import("std");
const builtin = @import("builtin");

fn createEmsdkStep(b: *std.Build, emsdk: *std.Build.Dependency) *std.Build.Step.Run {
    if (builtin.os.tag == .windows) {
        return b.addSystemCommand(&.{emsdk.path(b.pathJoin(&.{"emsdk.bat"})).getPath(b)});
    } else {
        const step = b.addSystemCommand(&.{"bash"});
        step.addArg(emsdk.path(b.pathJoin(&.{"emsdk"})).getPath(b));
        return step;
    }
}

fn createEmcc(
    b: *std.Build,
    emsdk: *std.Build.Dependency,
) *std.Build.Step.Run {
    if (builtin.os.tag == .windows) {
        // emcc.bat workaround
        const em_py = emsdk.path(b.pathJoin(&.{ "python", "3.9.2-nuget_64bit", "python.exe" })).getPath(b);
        const emcc_py = emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", "emcc.py" })).getPath(b);
        return b.addSystemCommand(&.{ em_py, emcc_py });
    } else {
        const emcc_path = emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", "emcc" })).getPath(b);
        return b.addSystemCommand(&.{emcc_path});
    }
}

// One-time setup of the Emscripten SDK (runs 'emsdk install + activate'). If the
// SDK had to be setup, a run step will be returned which should be added
// as dependency to the sokol library (since this needs the emsdk in place),
// if the emsdk was already setup, null will be returned.
// NOTE: ideally this would go into a separate emsdk-zig package
// NOTE 2: the file exists check is a bit hacky, it would be cleaner
// to build an on-the-fly helper tool which takes care of the SDK
// setup and just does nothing if it already happened
// NOTE 3: this code works just fine when the SDK version is updated in build.zig.zon
// since this will be cloned into a new zig cache directory which doesn't have
// an .emscripten file yet until the one-time setup.
pub fn emSdkSetupStep(b: *std.Build, emsdk: *std.Build.Dependency) !?*std.Build.Step.Run {
    const dot_emsc_path = emsdk.path(b.pathJoin(&.{".emscripten"})).getPath(b);
    const dot_emsc_exists = !std.meta.isError(std.fs.accessAbsolute(dot_emsc_path, .{}));
    if (!dot_emsc_exists) {
        const emsdk_install = createEmsdkStep(b, emsdk);
        emsdk_install.addArgs(&.{ "install", "latest" });
        const emsdk_activate = createEmsdkStep(b, emsdk);
        emsdk_activate.addArgs(&.{ "activate", "latest" });
        emsdk_activate.step.dependOn(&emsdk_install.step);
        return emsdk_activate;
    } else {
        return null;
    }
}

// for wasm32-emscripten, need to run the Emscripten linker from the Emscripten SDK
// NOTE: ideally this would go into a separate emsdk-zig package
pub const EmLinkOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// the actual Zig code must be compiled to a static link library
    lib_main: *std.Build.Step.Compile,
    release_use_closure: bool = true,
    release_use_lto: bool = true,
    use_webgpu: bool = false,
    use_webgl2: bool = false,
    use_emmalloc: bool = false,
    use_filesystem: bool = true,
    // FIXME: this should be a LazyPath?
    shell_file_path: ?[]const u8 = null,
    extra_before: []const []const u8 = &.{},
    // for "-sSIDE_MODULE" placeholder
    extra_after: []const []const u8 = &.{},
};
/// *std.Build.Step.Compile(zig-out/lib/xxx.a) => xxx.wasm
pub fn emLinkStep(
    b: *std.Build,
    emsdk: *std.Build.Dependency,
    options: EmLinkOptions,
) !*std.Build.Step.InstallDir {
    const emcc = createEmcc(b, emsdk);
    if (try emSdkSetupStep(b, emsdk)) |setup| {
        emcc.step.dependOn(&setup.step);
    }
    emcc.setName("emcc"); // hide emcc path
    if (options.optimize == .Debug) {
        emcc.addArgs(&.{ "-Og", "-sSAFE_HEAP=1", "-sSTACK_OVERFLOW_CHECK=1" });
    } else {
        emcc.addArg("-sASSERTIONS=0");
        if (options.optimize == .ReleaseSmall) {
            emcc.addArg("-Oz");
        } else {
            emcc.addArg("-O3");
        }
        if (options.release_use_lto) {
            emcc.addArg("-flto");
        }
        if (options.release_use_closure) {
            emcc.addArgs(&.{ "--closure", "1" });
        }
    }
    if (options.use_webgpu) {
        emcc.addArg("-sUSE_WEBGPU=1");
    }
    if (options.use_webgl2) {
        emcc.addArg("-sUSE_WEBGL2=1");
    }
    if (!options.use_filesystem) {
        emcc.addArg("-sNO_FILESYSTEM=1");
    }
    if (options.use_emmalloc) {
        emcc.addArg("-sMALLOC='emmalloc'");
    }
    if (options.shell_file_path) |shell_file_path| {
        emcc.addArg(b.fmt("--shell-file={s}", .{shell_file_path}));
    }
    for (options.extra_before) |arg| {
        emcc.addArg(arg);
    }

    // add the main lib, and then scan for library dependencies and add those too
    emcc.addArtifactArg(options.lib_main);
    var it = options.lib_main.root_module.iterateDependencies(options.lib_main, false);
    while (it.next()) |item| {
        for (item.module.link_objects.items) |link_object| {
            switch (link_object) {
                .other_step => |compile_step| {
                    switch (compile_step.kind) {
                        .lib => {
                            emcc.addArtifactArg(compile_step);
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }

    emcc.addArg("-o");
    const out_file = emcc.addOutputFileArg(b.fmt("{s}.html", .{options.lib_main.name}));

    for (options.extra_after) |arg| {
        emcc.addArg(arg);
    }

    // the emcc linker creates 3 output files (.html, .wasm and .js)
    const install = b.addInstallDirectory(.{
        .source_dir = out_file.dirname(),
        .install_dir = .prefix,
        .install_subdir = "web",
    });
    install.step.dependOn(&emcc.step);

    return install;
}
