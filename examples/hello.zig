const std = @import("std");
const builtin = @import("builtin");

extern fn console_logger(level: c_int, ptr: *const u8, size: c_int) void;

fn extern_write(level: c_int, m: []const u8) error{}!usize {
    if (m.len > 0) {
        console_logger(level, &m[0], @intCast(m.len));
    }
    return m.len;
}

fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (builtin.target.cpu.arch == .wasm32) { // <- wasm のときだけ extern 関数にリダイレクトする
        const level = switch (message_level) {
            .err => 0,
            .warn => 1,
            .info => 2,
            .debug => 3,
        };
        const w = std.io.Writer(c_int, error{}, extern_write){
            .context = level,
        };
        w.print(format, args) catch |err| {
            const err_name = @errorName(err);
            extern_write(0, err_name) catch unreachable;
        };
        _ = extern_write(level, "\n") catch unreachable;
    } else {
        std.log.defaultLog(message_level, scope, format, args);
    }
}

fn hello() void {
    if (builtin.target.os.tag == .emscripten) {
        std.debug.print("hello: emscripten\n", .{});
    } else {
        const triple = builtin.target.linuxTriple(std.heap.page_allocator) catch @panic("tri");
        log(.info, .hoge, "hello: {s}", .{triple});
    }
}

pub fn main() void {
    hello();
}
