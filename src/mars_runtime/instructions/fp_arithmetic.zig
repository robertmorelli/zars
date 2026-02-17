const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    if (std.mem.eql(u8, op, "add.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f32 = @bitCast(u.read_fp_single(state, fs));
        const rhs: f32 = @bitCast(u.read_fp_single(state, ft));
        u.write_fp_single(state, fd, @bitCast(lhs + rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sub.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f32 = @bitCast(u.read_fp_single(state, fs));
        const rhs: f32 = @bitCast(u.read_fp_single(state, ft));
        u.write_fp_single(state, fd, @bitCast(lhs - rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mul.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f32 = @bitCast(u.read_fp_single(state, fs));
        const rhs: f32 = @bitCast(u.read_fp_single(state, ft));
        u.write_fp_single(state, fd, @bitCast(lhs * rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "div.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f32 = @bitCast(u.read_fp_single(state, fs));
        const rhs: f32 = @bitCast(u.read_fp_single(state, ft));
        u.write_fp_single(state, fd, @bitCast(lhs / rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sqrt.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(u.read_fp_single(state, fs));
        const result: f32 = if (value < 0.0) std.math.nan(f32) else @floatCast(@sqrt(@as(f64, value)));
        u.write_fp_single(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "add.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(u.read_fp_double(state, fs));
        const rhs: f64 = @bitCast(u.read_fp_double(state, ft));
        u.write_fp_double(state, fd, @bitCast(lhs + rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sub.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(u.read_fp_double(state, fs));
        const rhs: f64 = @bitCast(u.read_fp_double(state, ft));
        u.write_fp_double(state, fd, @bitCast(lhs - rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mul.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(u.read_fp_double(state, fs));
        const rhs: f64 = @bitCast(u.read_fp_double(state, ft));
        u.write_fp_double(state, fd, @bitCast(lhs * rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "div.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(u.read_fp_double(state, fs));
        const rhs: f64 = @bitCast(u.read_fp_double(state, ft));
        u.write_fp_double(state, fd, @bitCast(lhs / rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sqrt.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(u.read_fp_double(state, fs));
        const result: f64 = if (value < 0.0) std.math.nan(f64) else @sqrt(value);
        u.write_fp_double(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "abs.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const bits = u.read_fp_single(state, fs) & 0x7FFF_FFFF;
        u.write_fp_single(state, fd, bits);
        return .ok;
    }

    if (std.mem.eql(u8, op, "abs.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        u.write_fp_single(state, fd + 1, u.read_fp_single(state, fs + 1) & 0x7FFF_FFFF);
        u.write_fp_single(state, fd, u.read_fp_single(state, fs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "neg.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        u.write_fp_single(state, fd, u.read_fp_single(state, fs) ^ 0x8000_0000);
        return .ok;
    }

    if (std.mem.eql(u8, op, "neg.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        u.write_fp_single(state, fd + 1, u.read_fp_single(state, fs + 1) ^ 0x8000_0000);
        u.write_fp_single(state, fd, u.read_fp_single(state, fs));
        return .ok;
    }

    return null;
}
