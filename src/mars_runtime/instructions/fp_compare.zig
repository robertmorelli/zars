const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    if (std.mem.eql(u8, op, "c.eq.s")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        const lhs: f32 = @bitCast(u.read_fp_single(state, fs));
        const rhs: f32 = @bitCast(u.read_fp_single(state, ft));
        u.set_fp_condition_flag(state, cc, lhs == rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.le.s")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        const lhs: f32 = @bitCast(u.read_fp_single(state, fs));
        const rhs: f32 = @bitCast(u.read_fp_single(state, ft));
        u.set_fp_condition_flag(state, cc, lhs <= rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.lt.s")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        const lhs: f32 = @bitCast(u.read_fp_single(state, fs));
        const rhs: f32 = @bitCast(u.read_fp_single(state, ft));
        u.set_fp_condition_flag(state, cc, lhs < rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.eq.d")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(u.read_fp_double(state, fs));
        const rhs: f64 = @bitCast(u.read_fp_double(state, ft));
        u.set_fp_condition_flag(state, cc, lhs == rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.le.d")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(u.read_fp_double(state, fs));
        const rhs: f64 = @bitCast(u.read_fp_double(state, ft));
        u.set_fp_condition_flag(state, cc, lhs <= rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.lt.d")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(u.read_fp_double(state, fs));
        const rhs: f64 = @bitCast(u.read_fp_double(state, ft));
        u.set_fp_condition_flag(state, cc, lhs < rhs);
        return .ok;
    }

    return null;
}
