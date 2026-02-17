const std = @import("std");
const engine = @import("engine.zig");
const run_program = engine.run_program;
const StatusCode = engine.StatusCode;

test "engine executes integer arithmetic fixture" {
    // Sanity check for arithmetic + jal/jr helper flow.
    const program =
        \\main:
        \\    li $t0, 40
        \\    li $t1, 2
        \\    add $t2, $t0, $t1
        \\    move $a0, $t2
        \\    li $v0, 1
        \\    syscall
        \\    jal print_newline
        \\    li $v0, 10
        \\    syscall
        \\print_newline:
        \\    li $v0, 11
        \\    li $a0, 10
        \\    syscall
        \\    jr $ra
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("42\n\n", out[0..result.output_len_bytes]);
}

test "engine reports runtime error on addi overflow" {
    // Signed add-immediate must trap on overflow.
    const program =
        \\main:
        \\    li   $t0, 2147483647
        \\    addi $t1, $t0, 1
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine keeps hi lo unchanged on div by zero" {
    // MIPS leaves HI/LO unchanged when divisor is zero.
    const program =
        \\main:
        \\    li   $t0, 0x11111111
        \\    li   $t1, 0x22222222
        \\    mthi $t0
        \\    mtlo $t1
        \\    li   $t2, 123
        \\    li   $t3, 0
        \\    div  $t2, $t3
        \\    mfhi $a0
        \\    li   $v0, 34
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    mflo $a0
        \\    li   $v0, 34
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
    try std.testing.expectEqualStrings("0x11111111\n0x22222222\n", out[0..result.output_len_bytes]);
}

test "engine executes immediate logical instruction group" {
    // Covers zero/sign extension behavior across immediate instruction family.
    const program =
        \\main:
        \\    li   $t0, -1
        \\    andi $t1, $t0, 0xff00
        \\    ori  $t2, $zero, 0x1234
        \\    xori $t3, $t2, 0x00ff
        \\    li   $t4, -5
        \\    slti $t5, $t4, -4
        \\    sltiu $t6, $t4, -4
        \\    lui  $t7, 0x1234
        \\    li   $v0, 1
        \\    move $a0, $t1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t5
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t6
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t7
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
    try std.testing.expectEqualStrings("65280\n4811\n1\n1\n305397760\n", out[0..result.output_len_bytes]);
}

test "engine executes variable shifts" {
    // Covers variable shift mask behavior (`& 0x1F`) for all three variants.
    const program =
        \\main:
        \\    li   $t0, -16
        \\    li   $t1, 2
        \\    sllv $t2, $t0, $t1
        \\    srlv $t3, $t0, $t1
        \\    srav $t4, $t0, $t1
        \\    li   $v0, 1
        \\    move $a0, $t2
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t4
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
    try std.testing.expectEqualStrings("-64\n1073741820\n-4\n", out[0..result.output_len_bytes]);
}

test "engine executes multiply accumulate and leading-bit operations" {
    const program =
        \\main:
        \\    li    $t0, 3
        \\    li    $t1, 4
        \\    mul   $t2, $t0, $t1
        \\    mflo  $s0
        \\    mthi  $zero
        \\    mtlo  $zero
        \\    li    $t3, -1
        \\    li    $t4, 2
        \\    maddu $t3, $t4
        \\    mfhi  $s1
        \\    mflo  $s2
        \\    clo   $s3, $t3
        \\    clz   $s4, $t4
        \\    li    $v0, 1
        \\    move  $a0, $s0
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    li    $v0, 34
        \\    move  $a0, $s1
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    li    $v0, 34
        \\    move  $a0, $s2
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    li    $v0, 1
        \\    move  $a0, $s3
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    li    $v0, 1
        \\    move  $a0, $s4
        \\    syscall
        \\    li    $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "12\n0x00000001\n0xfffffffe\n32\n30\n",
        out[0..result.output_len_bytes],
    );
}
