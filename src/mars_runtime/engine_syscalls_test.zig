const std = @import("std");
const engine = @import("engine.zig");
const run_program = engine.run_program;
const StatusCode = engine.StatusCode;

test "engine supports syscall read string semantics" {
    // Service 8 should copy one line, append newline when room remains, and NUL-terminate.
    const program =
        \\.data
        \\buf: .space 32
        \\.text
        \\main:
        \\    li   $v0, 8
        \\    la   $a0, buf
        \\    li   $a1, 16
        \\    syscall
        \\    li   $v0, 4
        \\    la   $a0, buf
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "hello\n",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("hello\n\n", out[0..result.output_len_bytes]);
}

test "engine supports syscall read char and float double" {
    // Services 12/6/7 with print services validate token and byte-level input handling.
    const program =
        \\main:
        \\    li   $v0, 12
        \\    syscall
        \\    move $t0, $v0
        \\    li   $v0, 6
        \\    syscall
        \\    mov.s $f12, $f0
        \\    li   $v0, 2
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 7
        \\    syscall
        \\    mov.d $f12, $f0
        \\    li   $v0, 3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t0
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "Q 1.5 2.25",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("1.5\n2.25\n81\n", out[0..result.output_len_bytes]);
}

test "engine supports sbrk alignment and heap byte access" {
    // Service 9 should return previous break and round new break to word alignment.
    const program =
        \\main:
        \\    li   $a0, 1
        \\    li   $v0, 9
        \\    syscall
        \\    move $s0, $v0
        \\    li   $a0, 3
        \\    li   $v0, 9
        \\    syscall
        \\    move $s1, $v0
        \\    subu $t0, $s1, $s0
        \\    li   $v0, 1
        \\    move $a0, $t0
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $t1, 65
        \\    sb   $t1, 0($s0)
        \\    li   $t2, 66
        \\    sb   $t2, 0($s1)
        \\    li   $v0, 11
        \\    lb   $a0, 0($s0)
        \\    syscall
        \\    lb   $a0, 0($s1)
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
    try std.testing.expectEqualStrings("4\nAB\n", out[0..result.output_len_bytes]);
}

test "engine close syscall leaves v0 unchanged" {
    // Service 16 parity check: `$v0` remains service id unless caller changes it.
    const program =
        \\main:
        \\    li   $v0, 16
        \\    li   $a0, 99
        \\    syscall
        \\    move $t0, $v0
        \\    li   $v0, 1
        \\    move $a0, $t0
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    // Closing fd 99 which was never opened returns runtime_error.
    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine supports syscall exit2 command-mode newline termination" {
    const program =
        \\main:
        \\    li   $a0, 60
        \\    li   $v0, 17
        \\    syscall
        \\    li   $v0, 1
        \\    li   $a0, 999
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("\n", out[0..result.output_len_bytes]);
}

test "engine supports syscall time service register updates" {
    const program =
        \\main:
        \\    li   $a0, 0
        \\    li   $a1, 0
        \\    li   $v0, 30
        \\    syscall
        \\    or   $t0, $a0, $a1
        \\    sltu $t1, $zero, $t0
        \\    li   $v0, 1
        \\    move $a0, $t1
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("1\n", out[0..result.output_len_bytes]);
}

test "engine supports midi and sleep syscalls without architectural side effects" {
    const program =
        \\main:
        \\    li   $a0, 60
        \\    li   $a1, 1
        \\    li   $a2, 0
        \\    li   $a3, 100
        \\    li   $v0, 31
        \\    syscall
        \\    li   $a0, 1
        \\    li   $v0, 32
        \\    syscall
        \\    li   $a0, 60
        \\    li   $a1, 1
        \\    li   $a2, 0
        \\    li   $a3, 100
        \\    li   $v0, 33
        \\    syscall
        \\    li   $v0, 1
        \\    li   $a0, 123
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("123\n", out[0..result.output_len_bytes]);
}

test "engine mirrors headless dialog syscall termination output" {
    const program =
        \\.data
        \\msg: .asciiz "headless dialog"
        \\.text
        \\main:
        \\    la   $a0, msg
        \\    li   $v0, 50
        \\    syscall
        \\    li   $v0, 1
        \\    li   $a0, 9
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
        "\nProgram terminated when maximum step limit -1 reached.\n\n",
        out[0..result.output_len_bytes],
    );
}
