const std = @import("std");
const build_emsdk = @import("build_emsdk.zig");
const emSdkSetupStep = build_emsdk.emSdkSetupStep;
pub const EmLinkOptions = build_emsdk.EmLinkOptions;
pub const emLinkCommand = build_emsdk.emLinkCommand;
pub const emLinkStep = build_emsdk.emLinkStep;
pub const emRunStep = build_emsdk.emRunStep;

pub fn build(b: *std.Build) !void {
    const emsdk = b.dependency("emsdk", .{});
    if (try emSdkSetupStep(b, emsdk)) |run| {
        // https://github.com/ziglang/zig/issues/5202
        b.default_step.dependOn(&run.step);
    }

    const build_examples = if (b.option(bool, "examples", "build examples")) |enable|
        enable
    else
        false;
    if (build_examples) {
        const examples = @import("examples/build.zig");
        try examples.build(b);
    }
}
