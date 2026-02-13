//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const mars_globals = @import("mars_runtime/globals.zig");
pub const instruction_word = @import("mars_runtime/instruction_word.zig");
pub const runtime_state = @import("mars_runtime/runtime_state.zig");
pub const engine = @import("mars_runtime/engine.zig");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

test "runtime seed modules are reachable" {
    mars_globals.validate_invariants();

    const syscall_word = instruction_word.encode_syscall(0xABCDE);
    try std.testing.expect(instruction_word.is_syscall(syscall_word));
}
