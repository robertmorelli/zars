const std = @import("std");
const engine = @import("engine.zig");
const run_program = engine.run_program;
const StatusCode = engine.StatusCode;

test "engine raises runtime error on taken trap instruction" {
    const program =
        \\main:
        \\    li  $t0, 1
        \\    li  $t1, 1
        \\    teq $t0, $t1
        \\    li  $v0, 10
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

test "engine source break instruction triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $a0, 77
        \\    jal  print_int_line
        \\    break
        \\    li   $a0, 88
        \\    jal  print_int_line
        \\    li   $v0, 10
        \\    syscall
        \\print_int_line:
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    jr   $ra
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
    try std.testing.expectEqualStrings("77\n", out[0..result.output_len_bytes]);
}

test "engine mulou immediate overflow triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li    $a0, 1
        \\    jal   print_int_line
        \\    li    $t0, 0x7fffffff
        \\    mulou $t1, $t0, 4
        \\    li    $a0, 2
        \\    jal   print_int_line
        \\    li    $v0, 10
        \\    syscall
        \\print_int_line:
        \\    li    $v0, 1
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    jr    $ra
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
    try std.testing.expectEqualStrings("1\n", out[0..result.output_len_bytes]);
}

test "engine unknown source mnemonic returns parse error" {
    const program =
        \\.text
        \\main:
        \\    frobnicate $t0, $t1, $t2
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.parse_error, result.status);
}

test "engine unknown syscall service returns runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $v0, 999
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
