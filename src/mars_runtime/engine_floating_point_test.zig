const std = @import("std");
const engine = @import("engine.zig");
const run_program = engine.run_program;
const StatusCode = engine.StatusCode;

test "engine handles fp condition flag branch variants" {
    const program =
        \\.data
        \\one: .float 1.0
        \\two: .float 2.0
        \\.text
        \\main:
        \\    l.s   $f0, one
        \\    l.s   $f1, two
        \\    li    $s0, 0
        \\    c.lt.s 1, $f1, $f0
        \\    bc1f  1, flag_false
        \\    nop
        \\    li    $s0, 99
        \\flag_false:
        \\    addiu $s0, $s0, 7
        \\    li    $v0, 1
        \\    move  $a0, $s0
        \\    syscall
        \\    li    $v0, 10
        \\    syscall
    ;

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("7\n", out[0..result.output_len_bytes]);
}

test "engine supports cp0 transfer and eret flow" {
    const program =
        \\main:
        \\    li   $t0, 0x00000002
        \\    mtc0 $t0, $12
        \\    la   $t1, target
        \\    mtc0 $t1, $14
        \\    eret
        \\    li   $v0, 1
        \\    li   $a0, 999
        \\    syscall
        \\target:
        \\    mfc0 $t2, $12
        \\    li   $v0, 1
        \\    move $a0, $t2
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("0\n", out[0..result.output_len_bytes]);
}

test "engine executes fp missing ops coverage program" {
    const program = @embedFile("../test_programs/fp_missing_ops.s");

    var out: [1024]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "2\n5\n4\n3\n3\n3\n3\n4\n3\n3\n4\n2\n0\n0x40400000\n0x40800000\n0x41100000\n4\n2\n\n",
        out[0..result.output_len_bytes],
    );
}
