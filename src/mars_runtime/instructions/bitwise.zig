const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    if (std.mem.eql(u8, op, "and")) {
        return u.execute_bitwise_op(state, instruction, u.bitwise_and);
    }

    if (std.mem.eql(u8, op, "or")) {
        return u.execute_bitwise_op(state, instruction, u.bitwise_or);
    }

    if (std.mem.eql(u8, op, "andi")) {
        if (instruction.operand_count == 3) {
            const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            const lhs: u32 = @bitCast(u.read_reg(state, rs));
            const imm = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
            if (u.delay_slot_active(state)) {
                if (u.immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    u.write_reg(state, rt, @bitCast(lhs & imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                u.write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (u.immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            u.write_reg(state, rt, @bitCast(lhs & rhs));
            return .ok;
        }
        if (instruction.operand_count == 2) {
            const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
            const lhs: u32 = @bitCast(u.read_reg(state, rt));
            const imm = u.parse_immediate(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            if (u.delay_slot_active(state)) {
                if (u.immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    u.write_reg(state, rt, @bitCast(lhs & imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                u.write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (u.immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            u.write_reg(state, rt, @bitCast(lhs & rhs));
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "ori")) {
        if (instruction.operand_count == 3) {
            const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            const lhs: u32 = @bitCast(u.read_reg(state, rs));
            const imm = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
            if (u.delay_slot_active(state)) {
                if (u.immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    u.write_reg(state, rt, @bitCast(lhs | imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                u.write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (u.immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            u.write_reg(state, rt, @bitCast(lhs | rhs));
            return .ok;
        }
        if (instruction.operand_count == 2) {
            const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
            const lhs: u32 = @bitCast(u.read_reg(state, rt));
            const imm = u.parse_immediate(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            if (u.delay_slot_active(state)) {
                if (u.immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    u.write_reg(state, rt, @bitCast(lhs | imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                u.write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (u.immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            u.write_reg(state, rt, @bitCast(lhs | rhs));
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "xor")) {
        return u.execute_bitwise_op(state, instruction, u.bitwise_xor);
    }

    if (std.mem.eql(u8, op, "xori")) {
        if (instruction.operand_count == 3) {
            const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            const lhs: u32 = @bitCast(u.read_reg(state, rs));
            const imm = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
            if (u.delay_slot_active(state)) {
                if (u.immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    u.write_reg(state, rt, @bitCast(lhs ^ imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                u.write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (u.immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            u.write_reg(state, rt, @bitCast(lhs ^ rhs));
            return .ok;
        }
        if (instruction.operand_count == 2) {
            const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
            const lhs: u32 = @bitCast(u.read_reg(state, rt));
            const imm = u.parse_immediate(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            if (u.delay_slot_active(state)) {
                if (u.immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    u.write_reg(state, rt, @bitCast(lhs ^ imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                u.write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (u.immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            u.write_reg(state, rt, @bitCast(lhs ^ rhs));
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "nor")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        u.write_reg(state, rd, @bitCast(~(lhs | rhs)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sll")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const shamt_i32 = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
        const shamt: u5 = @intCast(shamt_i32);
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        u.write_reg(state, rd, @bitCast(rhs << shamt));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sllv")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const shamt: u5 = @intCast(@as(u32, @bitCast(u.read_reg(state, rs))) & u.mask_shift_amount);
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        u.write_reg(state, rd, @bitCast(rhs << shamt));
        return .ok;
    }

    if (std.mem.eql(u8, op, "srl")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const shamt_i32 = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
        const shamt: u5 = @intCast(shamt_i32);
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        u.write_reg(state, rd, @bitCast(rhs >> shamt));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sra")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const shamt_i32 = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
        const shamt: u5 = @intCast(shamt_i32);
        u.write_reg(state, rd, u.read_reg(state, rt) >> shamt);
        return .ok;
    }

    if (std.mem.eql(u8, op, "srav")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const shamt: u5 = @intCast(@as(u32, @bitCast(u.read_reg(state, rs))) & u.mask_shift_amount);
        u.write_reg(state, rd, u.read_reg(state, rt) >> shamt);
        return .ok;
    }

    if (std.mem.eql(u8, op, "srlv")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const shamt: u5 = @intCast(@as(u32, @bitCast(u.read_reg(state, rs))) & u.mask_shift_amount);
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        u.write_reg(state, rd, @bitCast(rhs >> shamt));
        return .ok;
    }

    if (std.mem.eql(u8, op, "rol")) {
        // Rotate-left pseudo-op with immediate or register shift count.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            if (u.parse_register(rhs_operand)) |rs| {
                // Register form first word is `subu $at, $zero, rs`.
                u.write_reg(state, 1, 0 -% u.read_reg(state, rs));
                return .ok;
            }
            const shamt_i32 = u.parse_immediate(rhs_operand) orelse return .parse_error;
            if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
            const shift_i32 = 32 - shamt_i32;
            if (shift_i32 == 32) {
                u.write_reg(state, 1, 0);
                return .ok;
            }
            const shift: u5 = @intCast(shift_i32);
            const value: u32 = @bitCast(u.read_reg(state, rt));
            u.write_reg(state, 1, @bitCast(value >> shift));
            return .ok;
        }
        const shamt: u5 = if (u.parse_register(rhs_operand)) |rs|
            @intCast(@as(u32, @bitCast(u.read_reg(state, rs))) & 0x1F)
        else blk: {
            const shamt_i32 = u.parse_immediate(rhs_operand) orelse return .parse_error;
            if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
            break :blk @intCast(shamt_i32);
        };
        const value: u32 = @bitCast(u.read_reg(state, rt));
        u.write_reg(state, rd, @bitCast(std.math.rotl(u32, value, shamt)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ror")) {
        // Rotate-right pseudo-op with immediate or register shift count.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            if (u.parse_register(rhs_operand)) |rs| {
                // Register form first word is `subu $at, $zero, rs`.
                u.write_reg(state, 1, 0 -% u.read_reg(state, rs));
                return .ok;
            }
            const shamt_i32 = u.parse_immediate(rhs_operand) orelse return .parse_error;
            if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
            const shift_i32 = 32 - shamt_i32;
            if (shift_i32 == 32) {
                u.write_reg(state, 1, 0);
                return .ok;
            }
            const shift: u5 = @intCast(shift_i32);
            const value: u32 = @bitCast(u.read_reg(state, rt));
            u.write_reg(state, 1, @bitCast(value << shift));
            return .ok;
        }
        const shamt: u5 = if (u.parse_register(rhs_operand)) |rs|
            @intCast(@as(u32, @bitCast(u.read_reg(state, rs))) & 0x1F)
        else blk: {
            const shamt_i32 = u.parse_immediate(rhs_operand) orelse return .parse_error;
            if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
            break :blk @intCast(shamt_i32);
        };
        const value: u32 = @bitCast(u.read_reg(state, rt));
        u.write_reg(state, rd, @bitCast(std.math.rotr(u32, value, shamt)));
        return .ok;
    }

    return null;
}
