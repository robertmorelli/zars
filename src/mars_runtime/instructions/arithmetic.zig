const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    // Integer arithmetic and logical group.
    if (std.mem.eql(u8, op, "add")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.parse_register(u.instruction_operand(instruction, 2))) |rt| {
            const lhs = u.read_reg(state, rs);
            const rhs = u.read_reg(state, rt);
            const sum = lhs +% rhs;
            if (u.signed_add_overflow(lhs, rhs, sum)) return .runtime_error;
            u.write_reg(state, rd, sum);
            return .ok;
        }
        const imm = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.delay_slot_active(state)) {
            if (u.immediate_fits_signed_16(imm)) {
                // 16-bit pseudo form first word is `addi rd, rs, imm`.
                const lhs = u.read_reg(state, rs);
                const sum = lhs +% imm;
                if (u.signed_add_overflow(lhs, imm, sum)) return .runtime_error;
                u.write_reg(state, rd, sum);
                return .ok;
            }
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            u.load_at_high_bits_only(state, imm);
            return .ok;
        }
        const lhs = u.read_reg(state, rs);
        const sum = lhs +% imm;
        if (u.signed_add_overflow(lhs, imm, sum)) return .runtime_error;
        u.write_reg(state, rd, sum);
        return .ok;
    }

    if (std.mem.eql(u8, op, "addi")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.delay_slot_active(state) and !u.immediate_fits_signed_16(imm)) {
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            u.load_at_high_bits_only(state, imm);
            return .ok;
        }
        const lhs = u.read_reg(state, rs);
        const sum = lhs +% imm;
        if (u.signed_add_overflow(lhs, imm, sum)) return .runtime_error;
        u.write_reg(state, rt, sum);
        return .ok;
    }

    if (std.mem.eql(u8, op, "subi")) {
        // Pseudo-op alias for addi with negated immediate.
        if (instruction.operand_count != 3) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.delay_slot_active(state)) {
            if (u.immediate_fits_signed_16(imm)) {
                // 16-bit pseudo form first word is `addi $at, $zero, imm`.
                u.write_reg(state, u.reg_at, imm);
                return .ok;
            }
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            u.load_at_high_bits_only(state, imm);
            return .ok;
        }
        const neg_imm = -%imm;
        const lhs = u.read_reg(state, rs);
        const sum = lhs +% neg_imm;
        if (u.signed_add_overflow(lhs, neg_imm, sum)) return .runtime_error;
        u.write_reg(state, rt, sum);
        return .ok;
    }

    if (std.mem.eql(u8, op, "addu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.parse_register(u.instruction_operand(instruction, 2))) |rt| {
            u.write_reg(state, rd, u.read_reg(state, rs) +% u.read_reg(state, rt));
            return .ok;
        }
        const imm = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.delay_slot_active(state)) {
            // Immediate pseudo form first word is always `lui $at, high(imm)`.
            u.load_at_high_bits_only(state, imm);
            return .ok;
        }
        u.write_reg(state, rd, u.read_reg(state, rs) +% imm);
        return .ok;
    }

    if (std.mem.eql(u8, op, "sub")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state) and u.parse_register(rhs_operand) == null) {
            const imm = u.parse_immediate(rhs_operand) orelse return .parse_error;
            if (u.immediate_fits_signed_16(imm)) {
                // 16-bit pseudo form first word is `addi $at, $zero, imm`.
                u.write_reg(state, u.reg_at, imm);
                return .ok;
            }
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            u.load_at_high_bits_only(state, imm);
            return .ok;
        }
        const rhs = if (u.parse_register(rhs_operand)) |rt|
            u.read_reg(state, rt)
        else
            u.parse_immediate(rhs_operand) orelse return .parse_error;
        const lhs = u.read_reg(state, rs);
        const dif = lhs -% rhs;
        if (u.signed_sub_overflow(lhs, rhs, dif)) return .runtime_error;
        u.write_reg(state, rd, dif);
        return .ok;
    }

    if (std.mem.eql(u8, op, "subu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.delay_slot_active(state) and u.parse_register(u.instruction_operand(instruction, 2)) == null) {
            // Immediate pseudo form first word is always `lui $at, high(imm)`.
            const imm = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
            u.load_at_high_bits_only(state, imm);
            return .ok;
        }
        const rhs = if (u.parse_register(u.instruction_operand(instruction, 2))) |rt|
            u.read_reg(state, rt)
        else
            u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        u.write_reg(state, rd, u.read_reg(state, rs) -% rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "addiu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.delay_slot_active(state) and !u.immediate_fits_signed_16(imm)) {
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            u.load_at_high_bits_only(state, imm);
            return .ok;
        }
        u.write_reg(state, rt, u.read_reg(state, rs) +% imm);
        return .ok;
    }

    if (std.mem.eql(u8, op, "subiu")) {
        // Pseudo-op alias for 32-bit immediate subtraction without overflow trap.
        if (instruction.operand_count != 3) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = u.parse_immediate(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.delay_slot_active(state)) {
            // Immediate pseudo form first word is always `lui $at, high(imm)`.
            u.load_at_high_bits_only(state, imm);
            return .ok;
        }
        u.write_reg(state, rt, u.read_reg(state, rs) -% imm);
        return .ok;
    }

    // Small arithmetic pseudo-instruction helpers.
    if (std.mem.eql(u8, op, "neg")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs = u.read_reg(state, rs);
        const dif = 0 -% rhs;
        if (u.signed_sub_overflow(0, rhs, dif)) return .runtime_error;
        u.write_reg(state, rd, dif);
        return .ok;
    }

    if (std.mem.eql(u8, op, "abs")) {
        // Integer absolute value pseudo-op.
        if (instruction.operand_count != 2) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word: `sra $at, rs, 31`.
            u.write_reg(state, u.reg_at, u.read_reg(state, rs) >> 31);
            return .ok;
        }
        const value = u.read_reg(state, rs);
        u.write_reg(state, rd, if (value < 0) -%value else value);
        return .ok;
    }

    if (std.mem.eql(u8, op, "negu")) {
        // Unsigned negate pseudo-op alias (`subu $rd, $zero, $rs`).
        if (instruction.operand_count != 2) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        u.write_reg(state, rd, 0 -% u.read_reg(state, rs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "not")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(u.read_reg(state, rs));
        u.write_reg(state, rd, @bitCast(~value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "lui")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm16 = u.parse_imm16_bits(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        u.write_reg(state, rt, @bitCast(imm16 << 16));
        return .ok;
    }

    return null;
}
