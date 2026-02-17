const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    if (std.mem.eql(u8, op, "movn")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.read_reg(state, rt) != 0) {
            u.write_reg(state, rd, u.read_reg(state, rs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movz")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.read_reg(state, rt) == 0) {
            u.write_reg(state, rd, u.read_reg(state, rs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movf")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (!u.get_fp_condition_flag(state, cc)) {
            u.write_reg(state, rd, u.read_reg(state, rs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movt")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (u.get_fp_condition_flag(state, cc)) {
            u.write_reg(state, rd, u.read_reg(state, rs));
        }
        return .ok;
    }

    return null;
}
