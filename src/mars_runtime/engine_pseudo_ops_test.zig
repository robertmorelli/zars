const std = @import("std");
const engine = @import("engine.zig");
const run_program = engine.run_program;
const StatusCode = engine.StatusCode;
const estimate_la_word_count = engine.estimate_la_word_count;
const estimate_memory_operand_word_count = engine.estimate_memory_operand_word_count;

test "engine parser accepts set directive as no-op" {
    const program =
        \\.text
        \\.set noreorder
        \\main:
        \\    li   $v0, 1
        \\    li   $a0, 7
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
    try std.testing.expectEqualStrings("7\n", out[0..result.output_len_bytes]);
}

test "engine supports address expressions for la lw and sw" {
    const program =
        \\.data
        \\arr: .word 11, 22, 33, 44
        \\.text
        \\main:
        \\    lw   $t0, arr
        \\    lw   $t1, arr+4
        \\    li   $t8, 4
        \\    lw   $t2, arr($t8)
        \\    li   $v0, 1
        \\    move $a0, $t0
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t2
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $s0, 77
        \\    sw   $s0, arr+8
        \\    lw   $s1, arr+8
        \\    li   $v0, 1
        \\    move $a0, $s1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    la   $s2, arr
        \\    la   $s3, arr+12
        \\    la   $s4, ($s2)
        \\    la   $s5, 4($s2)
        \\    la   $s6, arr($t8)
        \\    subu $s3, $s3, $s2
        \\    subu $s4, $s4, $s2
        \\    subu $s5, $s5, $s2
        \\    subu $s6, $s6, $s2
        \\    li   $v0, 1
        \\    move $a0, $s3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $s4
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $s5
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $s6
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    la   $t3, 65535($zero)
        \\    la   $t4, -1($zero)
        \\    la   $t5, 65536
        \\    li   $v0, 34
        \\    move $a0, $t3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 34
        \\    move $a0, $t4
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 34
        \\    move $a0, $t5
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [512]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "11 22 22\n77\n12 0 4 4\n0x0000ffff 0xffffffff 0x00010000\n\n",
        out[0..result.output_len_bytes],
    );
}

test "engine address operand estimators match MARS reference forms" {
    try std.testing.expectEqual(@as(u32, 2), estimate_la_word_count("arr"));
    try std.testing.expectEqual(@as(u32, 1), estimate_la_word_count("($t0)"));
    try std.testing.expectEqual(@as(u32, 2), estimate_la_word_count("0($t0)"));
    try std.testing.expectEqual(@as(u32, 3), estimate_la_word_count("-1($t0)"));
    try std.testing.expectEqual(@as(u32, 2), estimate_la_word_count("65535($t0)"));
    try std.testing.expectEqual(@as(u32, 3), estimate_la_word_count("65536($t0)"));

    try std.testing.expectEqual(@as(u32, 2), estimate_memory_operand_word_count("arr"));
    try std.testing.expectEqual(@as(u32, 3), estimate_memory_operand_word_count("arr($zero)"));
    try std.testing.expectEqual(@as(u32, 3), estimate_memory_operand_word_count("arr($t0)"));
    try std.testing.expectEqual(@as(u32, 1), estimate_memory_operand_word_count("32767($t0)"));
    try std.testing.expectEqual(@as(u32, 3), estimate_memory_operand_word_count("65535($t0)"));
    try std.testing.expectEqual(@as(u32, 1), estimate_memory_operand_word_count("32767"));
    try std.testing.expectEqual(@as(u32, 2), estimate_memory_operand_word_count("65535"));
}

test "engine rejects label minus offset address forms" {
    const program =
        \\.data
        \\arr: .word 1
        \\.text
        \\main:
        \\    lw   $t0, arr-4($zero)
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.parse_error, result.status);
}

test "engine resolves end-of-text labels with pseudo-expanded counts" {
    const program =
        \\.text
        \\main:
        \\    la   $t0, tail
        \\    la   $t1, body
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
        \\body:
        \\    add  $s0, $s1, 100000
        \\tail:
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("12\n", out[0..result.output_len_bytes]);
}

test "engine estimates sne pseudo word counts from label deltas" {
    const program =
        \\.text
        \\main:
        \\    la   $t0, after_rr
        \\    la   $t1, before_rr
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    la   $t0, after_ri
        \\    la   $t1, before_ri
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    la   $t0, after_r32
        \\    la   $t1, before_r32
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
        \\before_rr:
        \\    sne  $s0, $s1, $s2
        \\after_rr:
        \\before_ri:
        \\    sne  $s0, $s1, 5
        \\after_ri:
        \\before_r32:
        \\    sne  $s0, $s1, 100000
        \\after_r32:
    ;

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("8\n12\n16\n", out[0..result.output_len_bytes]);
}

test "engine li with bit-31-set immediates expands to two words matching MARS" {
    // li with 32-bit hex values where bit 31 is set (negative as i32) must
    // expand to lui+ori (2 words), not addiu (which would miscount words and
    // shift all subsequent label addresses).
    const program =
        \\.text
        \\main:
        \\    la   $t0, after_zero_low
        \\    la   $t1, before_zero_low
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    la   $t0, after_nonzero_low
        \\    la   $t1, before_nonzero_low
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 34
        \\    move $a0, $t8
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 34
        \\    move $a0, $t9
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
        \\before_zero_low:
        \\    li   $t8, 0x82080000
        \\after_zero_low:
        \\before_nonzero_low:
        \\    li   $t9, 0x92090001
        \\after_nonzero_low:
    ;

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    // Each li should occupy 2 words = 8 bytes.
    // The loaded values must also be correct.
    // $t8 and $t9 are not loaded (their li instructions are after exit).
    try std.testing.expectEqualStrings("8\n8\n0x00000000\n0x00000000\n", out[0..result.output_len_bytes]);
}

test "engine executes mulou coverage program including immediate form" {
    const program = @embedFile("../test_programs/mulou_coverage.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("60000\n90000\n\n", out[0..result.output_len_bytes]);
}

test "engine executes pseudo div/rem forms coverage program" {
    const program = @embedFile("../test_programs/pseudo_div_rem_forms.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("6\n2\n6\n2\n4\n0\n2\n6\n77\n88\n77\n88\n\n", out[0..result.output_len_bytes]);
}

test "engine pseudo div register zero divisor triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $a0, 99
        \\    jal  print_int_line
        \\    li   $s0, 20
        \\    li   $s1, 0
        \\    div  $t0, $s0, $s1
        \\    li   $a0, 42
        \\    jal  print_int_line
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
    try std.testing.expectEqualStrings("99\n", out[0..result.output_len_bytes]);
}

test "engine pseudo divu register zero divisor triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $a0, 99
        \\    jal  print_int_line
        \\    li   $s0, 20
        \\    li   $s1, 0
        \\    divu $t0, $s0, $s1
        \\    li   $a0, 42
        \\    jal  print_int_line
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
    try std.testing.expectEqualStrings("99\n", out[0..result.output_len_bytes]);
}

test "engine pseudo rem register zero divisor triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $a0, 99
        \\    jal  print_int_line
        \\    li   $s0, 20
        \\    li   $s1, 0
        \\    rem  $t0, $s0, $s1
        \\    li   $a0, 42
        \\    jal  print_int_line
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
    try std.testing.expectEqualStrings("99\n", out[0..result.output_len_bytes]);
}

test "engine pseudo remu register zero divisor triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $a0, 99
        \\    jal  print_int_line
        \\    li   $s0, 20
        \\    li   $s1, 0
        \\    remu $t0, $s0, $s1
        \\    li   $a0, 42
        \\    jal  print_int_line
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
    try std.testing.expectEqualStrings("99\n", out[0..result.output_len_bytes]);
}

test "engine executes compare pseudo immediate forms outside delay slots" {
    const program =
        \\.text
        \\main:
        \\    li    $t0, 5
        \\    seq   $s0, $t0, 5
        \\    sne   $s1, $t0, 5
        \\    sge   $s2, $t0, 5
        \\    sgt   $s3, $t0, 5
        \\    sle   $s4, $t0, 5
        \\
        \\    li    $t1, -1
        \\    sgeu  $s5, $t1, 5
        \\    li    $t2, 1
        \\    sgtu  $s6, $t2, -1
        \\    sleu  $s7, $t2, -1
        \\
        \\    move  $a0, $s0
        \\    jal   print_int_line
        \\    move  $a0, $s1
        \\    jal   print_int_line
        \\    move  $a0, $s2
        \\    jal   print_int_line
        \\    move  $a0, $s3
        \\    jal   print_int_line
        \\    move  $a0, $s4
        \\    jal   print_int_line
        \\    move  $a0, $s5
        \\    jal   print_int_line
        \\    move  $a0, $s6
        \\    jal   print_int_line
        \\    move  $a0, $s7
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

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("1\n0\n1\n0\n1\n1\n0\n1\n\n", out[0..result.output_len_bytes]);
}

test "engine executes arithmetic and logical pseudo immediate forms outside delay slots" {
    const program =
        \\.text
        \\main:
        \\    li    $t0, 10
        \\    add   $s0, $t0, 100000
        \\    addu  $s1, $t0, 5
        \\    sub   $s2, $t0, 5
        \\    subu  $s3, $t0, 5
        \\    addi  $s4, $t0, 100000
        \\    addiu $s5, $t0, 100000
        \\    subi  $s6, $t0, 5
        \\    subiu $s7, $t0, 5
        \\    andi  $t1, $t0, 100000
        \\    ori   $t2, $t0, 100000
        \\    xori  $t3, $t0, 100000
        \\    andi  $t4, 100000
        \\    ori   $t5, 100000
        \\    xori  $t6, 100000
        \\    and   $t7, $t0, 255
        \\    or    $k0, $t0, 255
        \\    xor   $k1, $t0, 255
        \\
        \\    move  $a0, $s0
        \\    jal   print_int_line
        \\    move  $a0, $s1
        \\    jal   print_int_line
        \\    move  $a0, $s2
        \\    jal   print_int_line
        \\    move  $a0, $s3
        \\    jal   print_int_line
        \\    move  $a0, $s4
        \\    jal   print_int_line
        \\    move  $a0, $s5
        \\    jal   print_int_line
        \\    move  $a0, $s6
        \\    jal   print_int_line
        \\    move  $a0, $s7
        \\    jal   print_int_line
        \\    move  $a0, $t1
        \\    jal   print_int_line
        \\    move  $a0, $t2
        \\    jal   print_int_line
        \\    move  $a0, $t3
        \\    jal   print_int_line
        \\    move  $a0, $t4
        \\    jal   print_int_line
        \\    move  $a0, $t5
        \\    jal   print_int_line
        \\    move  $a0, $t6
        \\    jal   print_int_line
        \\    move  $a0, $t7
        \\    jal   print_int_line
        \\    move  $a0, $k0
        \\    jal   print_int_line
        \\    move  $a0, $k1
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

    var out: [512]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    // 2-operand ori/xori use $rd as both source and destination.
    // $t5 and $t6 are 0 initially, so ori $t5, 100000 = 0|100000 = 100000.
    try std.testing.expectEqualStrings(
        "100010\n15\n5\n5\n100010\n100010\n5\n5\n0\n100010\n100010\n0\n100000\n100000\n10\n255\n245\n\n",
        out[0..result.output_len_bytes],
    );
}
