const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    if (std.mem.eql(u8, op, "break")) {
        if (instruction.operand_count > 1) return .parse_error;
        return .runtime_error;
    }

    if (std.mem.eql(u8, op, "teq")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) == u.read_reg(state, rt)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "teqi")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = u.parse_signed_imm16(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) == imm) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tne")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) != u.read_reg(state, rt)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tnei")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = u.parse_signed_imm16(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) != imm) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tge")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) >= u.read_reg(state, rt)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tgeu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        if (lhs >= rhs) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tgei")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = u.parse_signed_imm16(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) >= imm) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tgeiu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = u.parse_signed_imm16(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(imm);
        if (lhs >= rhs) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tlt")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) < u.read_reg(state, rt)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tltu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        if (lhs < rhs) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tlti")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = u.parse_signed_imm16(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) < imm) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tltiu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = u.parse_signed_imm16(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(imm);
        if (lhs < rhs) return .runtime_error;
        return .ok;
    }

    return null;
}
