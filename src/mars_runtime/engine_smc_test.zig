const std = @import("std");
const engine = @import("engine.zig");
const run_program = engine.run_program;
const StatusCode = engine.StatusCode;

test "engine executes patched integer and hilo decode families" {
    const program = @embedFile("../test_programs/smc_patch_integer_hilo.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "19\n13\n1\n0\n196608\n2\n-1\n1\n48\n1\n-4\n30\n48\n",
        out[0..result.output_len_bytes],
    );
}

test "engine executes patched regimm and sign-branch decode families" {
    const program = @embedFile("../test_programs/smc_patch_regimm_branches.s");

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("6\n4194504\n", out[0..result.output_len_bytes]);
}

test "engine executes patched partial-memory decode families" {
    const program = @embedFile("../test_programs/smc_patch_partial_memory.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "68\n51\n13124\n13124\n1\n0x33441122\n0x33443333\n",
        out[0..result.output_len_bytes],
    );
}

test "engine executes patched trap and cp0 decode families" {
    const program = @embedFile("../test_programs/smc_patch_trap_cp0.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("9\n9\n2\n0\n", out[0..result.output_len_bytes]);
}

test "engine executes patched cop1 transfer and branch decode families" {
    const program = @embedFile("../test_programs/smc_patch_cop1_transfer_branch.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "1065353216\n1073741824\n0x3f800000\n",
        out[0..result.output_len_bytes],
    );
}

test "engine patched break triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $t8, 0x0000000D
        \\    la   $t9, slot_break
        \\    sw   $t8, 0($t9)
        \\    j    slot_break
        \\slot_break:
        \\    nop
        \\    li   $v0, 1
        \\    li   $a0, 999
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine patched teq true condition triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $s0, 7
        \\    li   $t8, 0x02100034
        \\    la   $t9, slot_teq
        \\    sw   $t8, 0($t9)
        \\    j    slot_teq
        \\slot_teq:
        \\    nop
        \\    li   $v0, 1
        \\    li   $a0, 999
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine patched teqi true condition triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $s0, 7
        \\    li   $t8, 0x060C0007
        \\    la   $t9, slot_teqi
        \\    sw   $t8, 0($t9)
        \\    j    slot_teqi
        \\slot_teqi:
        \\    nop
        \\    li   $v0, 1
        \\    li   $a0, 999
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine executes patched cop1 arithmetic and convert decode families" {
    const program = @embedFile("../test_programs/smc_patch_cop1_arith_convert.s");

    var out: [512]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "1077936128\n1065353216\n1073741824\n1073741824\n2\n1\n2\n0x3f800000\n0xbf800000\n",
        out[0..result.output_len_bytes],
    );
}

test "engine executes patched special2 accumulation decode families" {
    const program = @embedFile("../test_programs/smc_patch_special2_madd.s");

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("30\n60\n30\n0\n", out[0..result.output_len_bytes]);
}

test "engine patched reserved opcode returns runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $t8, 0xFC000000
        \\    la   $t9, slot_bad
        \\    sw   $t8, 0($t9)
        \\    j    slot_bad
        \\slot_bad:
        \\    nop
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

fn run_patched_decode_failure_case(word: u32) StatusCode {
    // Build the patched instruction with `lui/ori` so every 32-bit word can be tested.
    const upper_imm: u16 = @intCast((word >> 16) & 0xFFFF);
    const lower_imm: u16 = @intCast(word & 0xFFFF);
    var program_buffer: [512]u8 = undefined;
    const program = std.fmt.bufPrint(
        &program_buffer,
        \\.text
        \\main:
        \\    lui  $t8, 0x{X:0>4}
        \\    ori  $t8, $t8, 0x{X:0>4}
        \\    la   $t9, slot_bad
        \\    sw   $t8, 0($t9)
        \\    j    slot_bad
        \\slot_bad:
        \\    nop
        \\
    ,
        .{ upper_imm, lower_imm },
    ) catch unreachable;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });
    return result.status;
}

test "engine patched regimm unknown rt returns runtime error" {
    // opcode=0x01, rt=0x02 is unassigned in REGIMM decode.
    const status = run_patched_decode_failure_case(0x0402_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop0 unknown rs returns runtime error" {
    // opcode=0x10 with rs=0x1F is outside mfc0/mtc0/eret handling.
    const status = run_patched_decode_failure_case(0x43E0_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop1 branch likely form returns runtime error" {
    // opcode=0x11, rs=0x08, rt bit1 set corresponds to unsupported bc1fl/bc1tl forms.
    const status = run_patched_decode_failure_case(0x4502_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop1 fmt.s unknown funct returns runtime error" {
    // opcode=0x11, rs=0x10, funct=0x08 is not implemented for fmt.s in MARS core decode.
    const status = run_patched_decode_failure_case(0x4600_0008);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop1 fmt.d unknown funct returns runtime error" {
    // opcode=0x11, rs=0x11, funct=0x08 is not a valid fmt.d operation.
    const status = run_patched_decode_failure_case(0x4620_0008);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop1 fmt.w unknown funct returns runtime error" {
    // opcode=0x11, rs=0x14, funct=0x00 is outside cvt.s.w/cvt.d.w.
    const status = run_patched_decode_failure_case(0x4680_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop1 unknown rs returns runtime error" {
    // opcode=0x11, rs=0x1E is not a supported cop1 transfer/arithmetic group.
    const status = run_patched_decode_failure_case(0x47C0_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched unknown primary opcode returns runtime error" {
    // opcode=0x3F has no architectural decode in this runtime.
    const status = run_patched_decode_failure_case(0xFC00_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched special unknown funct returns runtime error" {
    // opcode=0x00 with funct=0x3F is outside this runtime's SPECIAL decode table.
    const status = run_patched_decode_failure_case(0x0000_003F);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched special2 unknown funct returns runtime error" {
    // opcode=0x1C with funct=0x3F is outside this runtime's SPECIAL2 decode table.
    const status = run_patched_decode_failure_case(0x7000_003F);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}
