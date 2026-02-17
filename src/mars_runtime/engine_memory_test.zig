const std = @import("std");
const engine = @import("engine.zig");
const run_program = engine.run_program;
const StatusCode = engine.StatusCode;

test "engine supports data directives ascii and align" {
    // `.ascii` length and `.align` padding should match text-visible addresses.
    const program =
        \\.data
        \\prefix: .ascii "AB"
        \\.align 2
        \\value_word: .word 0x11223344
        \\.text
        \\main:
        \\    la   $t0, prefix
        \\    la   $t1, value_word
        \\    subu $t2, $t1, $t0
        \\    li   $v0, 1
        \\    move $a0, $t2
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    lw   $a0, 0($t1)
        \\    li   $v0, 34
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("4\n0x11223344\n", out[0..result.output_len_bytes]);
}

test "engine executes partial-word memory instruction family" {
    const program =
        \\.data
        \\w: .word 0x11223344
        \\.text
        \\main:
        \\    la   $s0, w
        \\    ll   $t0, 0($s0)
        \\    sc   $t0, 0($s0)
        \\    move $t1, $t0
        \\    li   $t2, 0
        \\    lwl  $t2, 1($s0)
        \\    li   $t3, 0
        \\    lwr  $t3, 2($s0)
        \\    li   $v0, 34
        \\    move $a0, $t2
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 34
        \\    move $a0, $t3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t1
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    // Data stored little-endian: 0x11223344 → [0x44, 0x33, 0x22, 0x11].
    // lwl at byte 1 loads data[1..0] into upper bytes → 0x33440000.
    // lwr at byte 2 loads data[2..3] into lower bytes → 0x00001122.
    try std.testing.expectEqualStrings("0x33440000\n0x00001122\n1\n", out[0..result.output_len_bytes]);
}
