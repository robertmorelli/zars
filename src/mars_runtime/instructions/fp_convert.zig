const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    if (std.mem.eql(u8, op, "floor.w.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(u.read_fp_single(state, fs));
        var floor_value = u.fp_math.round_word_default_single(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f32, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f32, @floatFromInt(std.math.maxInt(i32))))
        {
            floor_value = @intFromFloat(@floor(value));
        }
        u.write_fp_single(state, fd, @bitCast(floor_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ceil.w.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(u.read_fp_single(state, fs));
        var ceil_value = u.fp_math.round_word_default_single(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f32, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f32, @floatFromInt(std.math.maxInt(i32))))
        {
            ceil_value = @intFromFloat(@ceil(value));
        }
        u.write_fp_single(state, fd, @bitCast(ceil_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "round.w.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(u.read_fp_single(state, fs));
        u.write_fp_single(state, fd, @bitCast(u.fp_math.round_to_nearest_even_single(value)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "trunc.w.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(u.read_fp_single(state, fs));
        var trunc_value = u.fp_math.round_word_default_single(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f32, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f32, @floatFromInt(std.math.maxInt(i32))))
        {
            trunc_value = @intFromFloat(@trunc(value));
        }
        u.write_fp_single(state, fd, @bitCast(trunc_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "floor.w.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(u.read_fp_double(state, fs));
        var floor_value = u.fp_math.round_word_default_double(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f64, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f64, @floatFromInt(std.math.maxInt(i32))))
        {
            floor_value = @intFromFloat(@floor(value));
        }
        u.write_fp_single(state, fd, @bitCast(floor_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ceil.w.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(u.read_fp_double(state, fs));
        var ceil_value = u.fp_math.round_word_default_double(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f64, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f64, @floatFromInt(std.math.maxInt(i32))))
        {
            ceil_value = @intFromFloat(@ceil(value));
        }
        u.write_fp_single(state, fd, @bitCast(ceil_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "round.w.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(u.read_fp_double(state, fs));
        u.write_fp_single(state, fd, @bitCast(u.fp_math.round_to_nearest_even_double(value)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "trunc.w.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(u.read_fp_double(state, fs));
        var trunc_value = u.fp_math.round_word_default_double(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f64, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f64, @floatFromInt(std.math.maxInt(i32))))
        {
            trunc_value = @intFromFloat(@trunc(value));
        }
        u.write_fp_single(state, fd, @bitCast(trunc_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.d.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        const value: f32 = @bitCast(u.read_fp_single(state, fs));
        const result: f64 = value;
        u.write_fp_double(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.d.w")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        const value: i32 = @bitCast(u.read_fp_single(state, fs));
        const result: f64 = @floatFromInt(value);
        u.write_fp_double(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.s.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(u.read_fp_double(state, fs));
        const result: f32 = @floatCast(value);
        u.write_fp_single(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.s.w")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: i32 = @bitCast(u.read_fp_single(state, fs));
        const result: f32 = @floatFromInt(value);
        u.write_fp_single(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.w.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(u.read_fp_double(state, fs));
        u.write_fp_single(state, fd, @bitCast(u.fp_math.java_double_to_i32_cast(value)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.w.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(u.read_fp_single(state, fs));
        u.write_fp_single(state, fd, @bitCast(u.fp_math.java_float_to_i32_cast(value)));
        return .ok;
    }

    return null;
}
