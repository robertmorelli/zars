// Central instruction dispatch aggregator.
// Imports all instruction group modules and dispatches opcodes through them.

const std = @import("std");
const u = @import("inst_util.zig");

const pseudo_ops = @import("pseudo_ops.zig");
const loads = @import("loads.zig");
const stores = @import("stores.zig");
const arithmetic = @import("arithmetic.zig");
const multiply_divide = @import("multiply_divide.zig");
const bitwise = @import("bitwise.zig");
const comparison = @import("comparison.zig");
const branches = @import("branches.zig");
const hilo = @import("hilo.zig");
const conditional_moves = @import("conditional_moves.zig");
const coprocessor = @import("coprocessor.zig");
const traps = @import("traps.zig");
const fp_arithmetic = @import("fp_arithmetic.zig");
const fp_convert = @import("fp_convert.zig");
const fp_move = @import("fp_move.zig");
const fp_compare = @import("fp_compare.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    return pseudo_ops.execute(parsed, state, instruction, op) orelse
        loads.execute(parsed, state, instruction, op) orelse
        stores.execute(parsed, state, instruction, op) orelse
        arithmetic.execute(parsed, state, instruction, op) orelse
        multiply_divide.execute(parsed, state, instruction, op) orelse
        bitwise.execute(parsed, state, instruction, op) orelse
        comparison.execute(parsed, state, instruction, op) orelse
        branches.execute(parsed, state, instruction, op) orelse
        hilo.execute(parsed, state, instruction, op) orelse
        conditional_moves.execute(parsed, state, instruction, op) orelse
        coprocessor.execute(parsed, state, instruction, op) orelse
        traps.execute(parsed, state, instruction, op) orelse
        fp_arithmetic.execute(parsed, state, instruction, op) orelse
        fp_convert.execute(parsed, state, instruction, op) orelse
        fp_move.execute(parsed, state, instruction, op) orelse
        fp_compare.execute(parsed, state, instruction, op);
}
