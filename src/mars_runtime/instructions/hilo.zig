const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    if (std.mem.eql(u8, op, "mflo")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        u.write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mfhi")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        u.write_reg(state, rd, state.hi);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mthi")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        state.hi = u.read_reg(state, rs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mtlo")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        state.lo = u.read_reg(state, rs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "clz")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(u.read_reg(state, rs));
        u.write_reg(state, rd, @intCast(@clz(value)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "clo")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(u.read_reg(state, rs));
        u.write_reg(state, rd, @intCast(@clz(~value)));
        return .ok;
    }

    return null;
}
