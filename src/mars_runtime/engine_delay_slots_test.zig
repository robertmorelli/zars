const std = @import("std");
const engine = @import("engine.zig");
const run_program = engine.run_program;
const StatusCode = engine.StatusCode;

test "engine delayed-slot multiword li executes first expansion word only" {
    const program = @embedFile("../test_programs/delay_slot_pseudo_li_db.s");

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("7\n\n", out[0..result.output_len_bytes]);
}

test "engine delayed-slot multiword mulu executes first expansion word only" {
    const program = @embedFile("../test_programs/delay_slot_pseudo_mulu_db.s");

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("123\n\n", out[0..result.output_len_bytes]);
}

test "engine delayed-slot compare and abs pseudo forms execute first expansion word only" {
    const program = @embedFile("../test_programs/delay_slot_pseudo_compare_abs_db.s");

    var out: [512]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "777\n-1\n0\n4\n1\n0\n1\n0\n77\n5\n77\n5\n77\n5\n77\n65536\n\n",
        out[0..result.output_len_bytes],
    );
}

test "engine delayed-slot arithmetic and logical pseudo immediate forms execute first expansion word only" {
    const program = @embedFile("../test_programs/delay_slot_pseudo_arith_logic_db.s");

    var out: [1024]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "15\n99\n65536\n99\n0\n99\n5\n99\n0\n99\n65536\n99\n65536\n99\n5\n99\n0\n52\n99\n65536\n99\n65536\n99\n65536\n99\n65536\n99\n65536\n\n",
        out[0..result.output_len_bytes],
    );
}

test "engine delayed-slot pseudo misc forms execute first expansion word only" {
    const program = @embedFile("../test_programs/delay_slot_pseudo_misc_db.s");

    var out: [1024]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "99\n4194304\n99\n65536\n99\n-4\n99\n1\n99\n-4\n99\n-2147483648\n287454020\n88\n-1716864052\n0\n99\n5\n99\n65536\n99\n5\n123\n456\n99\n5\n123\n456\n\n",
        out[0..result.output_len_bytes],
    );
}

test "engine delayed-slot register-divisor div/rem pseudo forms execute first expansion word only" {
    const program = @embedFile("../test_programs/delay_slot_pseudo_div_reg_db.s");

    var out: [512]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "99\n11\n22\n99\n33\n44\n99\n55\n66\n99\n77\n88\n99\n101\n202\n\n",
        out[0..result.output_len_bytes],
    );
}
