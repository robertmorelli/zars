// Instruction group: Store instructions
// Handles all MIPS store operations: sb, sh, ush, sw, usw, sd,
// swc1, sdc1, s.s, s.d, sc, swl, swr.

const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    if (std.mem.eql(u8, op, "sb")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(u.read_reg(state, rt));
        if (!u.write_u8(parsed, state, addr, @intCast(value & 0xFF))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sh")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 1) != 0) return .runtime_error;
        const value: u32 = @bitCast(u.read_reg(state, rt));
        if (!u.write_u16_be(parsed, state, addr, @intCast(value & 0xFFFF))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "ush")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(u.read_reg(state, rt));
        if (!u.write_u8(parsed, state, addr, @intCast(value & 0xFF))) return .runtime_error;
        if (!u.write_u8(parsed, state, addr + 1, @intCast((value >> 8) & 0xFF))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sw")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const value: u32 = @bitCast(u.read_reg(state, rt));
        if (!u.write_u32(parsed, state, addr, value)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "usw")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(u.read_reg(state, rt));
        if (!u.write_u8(parsed, state, addr, @intCast(value & 0xFF))) return .runtime_error;
        if (!u.write_u8(parsed, state, addr + 1, @intCast((value >> 8) & 0xFF))) return .runtime_error;
        if (!u.write_u8(parsed, state, addr + 2, @intCast((value >> 16) & 0xFF))) return .runtime_error;
        if (!u.write_u8(parsed, state, addr + 3, @intCast((value >> 24) & 0xFF))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sd")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        if (rt >= 31) return .runtime_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const low: u32 = @bitCast(u.read_reg(state, rt));
        const high: u32 = @bitCast(u.read_reg(state, rt + 1));
        if (!u.write_u32(parsed, state, addr, low)) return .runtime_error;
        if (!u.write_u32(parsed, state, addr + 4, high)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "swc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        if (!u.write_u32(parsed, state, addr, u.read_fp_single(state, ft))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sdc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(ft)) return .runtime_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 7) != 0) return .runtime_error;
        if (!u.write_u32(parsed, state, addr, u.read_fp_single(state, ft))) return .runtime_error;
        if (!u.write_u32(parsed, state, addr + 4, u.read_fp_single(state, ft + 1))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "s.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        if (!u.write_u32(parsed, state, addr, u.read_fp_single(state, ft))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "s.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const ft = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(ft)) return .runtime_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 7) != 0) return .runtime_error;
        if (!u.write_u32(parsed, state, addr, u.read_fp_single(state, ft))) return .runtime_error;
        if (!u.write_u32(parsed, state, addr + 4, u.read_fp_single(state, ft + 1))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sc")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const value: u32 = @bitCast(u.read_reg(state, rt));
        if (!u.write_u32(parsed, state, addr, value)) return .runtime_error;
        u.write_reg(state, rt, 1);
        return .ok;
    }

    if (std.mem.eql(u8, op, "swl")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const source: u32 = @bitCast(u.read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= mod_u2) : (i += 1) {
            const byte_index: u2 = @intCast(3 - i);
            if (!u.write_u8(parsed, state, address - i, u.fp_math.int_get_byte(source, byte_index))) return .runtime_error;
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "swr")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = u.resolve_load_address(parsed, state, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const source: u32 = @bitCast(u.read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= @as(u2, 3 - mod_u2)) : (i += 1) {
            if (!u.write_u8(parsed, state, address + i, u.fp_math.int_get_byte(source, i))) return .runtime_error;
        }
        return .ok;
    }

    return null;
}
