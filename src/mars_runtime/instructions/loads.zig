// Instruction group: Load instructions
// Handles all MIPS load operations: l.s, lwc1, l.d, ldc1, lb, lbu,
// lh, ulh, lhu, ulhu, lw, ulw, ld, ll, lwl, lwr.

const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    if (std.mem.eql(u8, op, "l.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value = u.read_u32_be(parsed, state, address) orelse return .runtime_error;
        u.write_fp_single(state, fd, value);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lwc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((address & 3) != 0) return .runtime_error;
        const value = u.read_u32_be(parsed, state, address) orelse return .runtime_error;
        u.write_fp_single(state, fd, value);
        return .ok;
    }

    if (std.mem.eql(u8, op, "l.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        const address = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((address & 7) != 0) return .runtime_error;
        const value = u.read_u64_be(parsed, state, address) orelse return .runtime_error;
        u.write_fp_double(state, fd, value);
        return .ok;
    }

    if (std.mem.eql(u8, op, "ldc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        const address = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((address & 7) != 0) return .runtime_error;
        const value_low = u.read_u32_be(parsed, state, address) orelse return .runtime_error;
        const value_high = u.read_u32_be(parsed, state, address + 4) orelse return .runtime_error;
        u.write_fp_single(state, fd, value_low);
        u.write_fp_single(state, fd + 1, value_high);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lb")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value_u8 = u.read_u8(parsed, state, addr) orelse return .runtime_error;
        const value_i8: i8 = @bitCast(value_u8);
        u.write_reg(state, rt, value_i8);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lbu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value_u8 = u.read_u8(parsed, state, addr) orelse return .runtime_error;
        u.write_reg(state, rt, value_u8);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lh")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 1) != 0) return .runtime_error;
        const value_u16 = u.read_u16_be(parsed, state, addr) orelse return .runtime_error;
        const value_i16: i16 = @bitCast(value_u16);
        u.write_reg(state, rt, value_i16);
        return .ok;
    }

    if (std.mem.eql(u8, op, "ulh")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value_u16 = u.read_u16_be(parsed, state, addr) orelse return .runtime_error;
        const value_i16: i16 = @bitCast(value_u16);
        u.write_reg(state, rt, value_i16);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lhu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 1) != 0) return .runtime_error;
        const value_u16 = u.read_u16_be(parsed, state, addr) orelse return .runtime_error;
        u.write_reg(state, rt, value_u16);
        return .ok;
    }

    if (std.mem.eql(u8, op, "ulhu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value_u16 = u.read_u16_be(parsed, state, addr) orelse return .runtime_error;
        u.write_reg(state, rt, value_u16);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lw")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const value = u.read_u32_be(parsed, state, addr) orelse return .runtime_error;
        u.write_reg(state, rt, @bitCast(value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ulw")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value = u.read_u32_be(parsed, state, addr) orelse return .runtime_error;
        u.write_reg(state, rt, @bitCast(value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ld")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        if (rt >= 31) return .runtime_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const low = u.read_u32_be(parsed, state, addr) orelse return .runtime_error;
        const high = u.read_u32_be(parsed, state, addr + 4) orelse return .runtime_error;
        u.write_reg(state, rt, @bitCast(low));
        u.write_reg(state, rt + 1, @bitCast(high));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ll")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const value = u.read_u32_be(parsed, state, addr) orelse return .runtime_error;
        u.write_reg(state, rt, @bitCast(value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "lwl")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        var result: u32 = @bitCast(u.read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= mod_u2) : (i += 1) {
            const source_byte = u.read_u8(parsed, state, address - i) orelse return .runtime_error;
            const byte_index: u2 = @intCast(3 - i);
            result = u.fp_math.int_set_byte(result, byte_index, source_byte);
        }
        u.write_reg(state, rt, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "lwr")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        var result: u32 = @bitCast(u.read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= @as(u2, 3 - mod_u2)) : (i += 1) {
            const source_byte = u.read_u8(parsed, state, address + i) orelse return .runtime_error;
            result = u.fp_math.int_set_byte(result, i, source_byte);
        }
        u.write_reg(state, rt, @bitCast(result));
        return .ok;
    }

    return null;
}
