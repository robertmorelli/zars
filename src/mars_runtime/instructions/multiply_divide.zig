const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    if (std.mem.eql(u8, op, "mult")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: i64 = u.read_reg(state, rs);
        const rhs: i64 = u.read_reg(state, rt);
        const product: i64 = lhs * rhs;
        state.lo = @intCast(product & u.mask_u32);
        state.hi = @intCast((product >> u.bits_per_word) & u.mask_u32);
        return .ok;
    }

    if (std.mem.eql(u8, op, "multu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u64 = @intCast(@as(u32, @bitCast(u.read_reg(state, rs))));
        const rhs: u64 = @intCast(@as(u32, @bitCast(u.read_reg(state, rt))));
        const product: u64 = lhs * rhs;
        state.lo = @bitCast(@as(u32, @intCast(product & u.mask_u32)));
        state.hi = @bitCast(@as(u32, @intCast((product >> u.bits_per_word) & u.mask_u32)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mul")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state) and u.parse_register(rhs_operand) == null) {
            const imm = u.parse_immediate(rhs_operand) orelse return .parse_error;
            if (u.immediate_fits_signed_16(imm)) {
                // 16-bit pseudo form first word is `addi $at, $zero, imm`.
                u.write_reg(state, 1, imm);
                return .ok;
            }
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            const imm_bits: u32 = @bitCast(imm);
            const high_only: u32 = imm_bits & 0xFFFF_0000;
            u.write_reg(state, 1, @bitCast(high_only));
            return .ok;
        }
        const rhs = if (u.parse_register(rhs_operand)) |rt|
            u.read_reg(state, rt)
        else
            u.parse_immediate(rhs_operand) orelse return .parse_error;
        const product: i64 = @as(i64, u.read_reg(state, rs)) * @as(i64, rhs);
        state.hi = @intCast((product >> u.bits_per_word) & u.mask_u32);
        state.lo = @intCast(product & u.mask_u32);
        u.write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mulu")) {
        // Pseudo-op alias for unsigned multiply low result with HI/LO side effects.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word.
            if (u.parse_register(rhs_operand)) |rt| {
                const lhs: u64 = @intCast(@as(u32, @bitCast(u.read_reg(state, rs))));
                const rhs: u64 = @intCast(@as(u32, @bitCast(u.read_reg(state, rt))));
                const product = lhs * rhs;
                state.hi = @bitCast(@as(u32, @truncate(product >> 32)));
                state.lo = @bitCast(@as(u32, @truncate(product)));
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        const lhs: u64 = @intCast(@as(u32, @bitCast(u.read_reg(state, rs))));
        const rhs: u64 = if (u.parse_register(rhs_operand)) |rt|
            @intCast(@as(u32, @bitCast(u.read_reg(state, rt))))
        else if (u.parse_immediate(rhs_operand)) |imm|
            @intCast(@as(u32, @bitCast(imm)))
        else
            return .parse_error;
        const product = lhs * rhs;
        state.hi = @bitCast(@as(u32, @truncate(product >> 32)));
        state.lo = @bitCast(@as(u32, @truncate(product)));
        u.write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mulo")) {
        // Signed multiply with overflow trap.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word.
            if (u.parse_register(rhs_operand)) |rt| {
                const product: i64 = @as(i64, u.read_reg(state, rs)) * @as(i64, u.read_reg(state, rt));
                state.hi = @intCast((product >> u.bits_per_word) & u.mask_u32);
                state.lo = @intCast(product & u.mask_u32);
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        const rhs: i64 = if (u.parse_register(rhs_operand)) |rt|
            @as(i64, u.read_reg(state, rt))
        else if (u.parse_immediate(rhs_operand)) |imm|
            @as(i64, imm)
        else
            return .parse_error;
        const product: i64 = @as(i64, u.read_reg(state, rs)) * rhs;
        if (product < std.math.minInt(i32) or product > std.math.maxInt(i32)) return .runtime_error;
        state.hi = @intCast((product >> u.bits_per_word) & u.mask_u32);
        state.lo = @intCast(product & u.mask_u32);
        u.write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mulou")) {
        // Unsigned multiply with overflow trap.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word.
            if (u.parse_register(rhs_operand)) |rt| {
                const lhs: u64 = @intCast(@as(u32, @bitCast(u.read_reg(state, rs))));
                const rhs: u64 = @intCast(@as(u32, @bitCast(u.read_reg(state, rt))));
                const product = lhs * rhs;
                state.hi = @bitCast(@as(u32, @truncate(product >> 32)));
                state.lo = @bitCast(@as(u32, @truncate(product)));
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        const lhs: u64 = @intCast(@as(u32, @bitCast(u.read_reg(state, rs))));
        const rhs: u64 = if (u.parse_register(rhs_operand)) |rt|
            @intCast(@as(u32, @bitCast(u.read_reg(state, rt))))
        else if (u.parse_immediate(rhs_operand)) |imm|
            @intCast(@as(u32, @bitCast(imm)))
        else
            return .parse_error;
        const product = lhs * rhs;
        if ((product >> 32) != 0) return .runtime_error;
        state.hi = 0;
        state.lo = @bitCast(@as(u32, @truncate(product)));
        u.write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "madd")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const product: i64 = @as(i64, u.read_reg(state, rs)) * @as(i64, u.read_reg(state, rt));
        const hi_bits: u32 = @bitCast(state.hi);
        const lo_bits: u32 = @bitCast(state.lo);
        const hilo_bits: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
        const hilo_signed: i64 = @bitCast(hilo_bits);
        const sum = hilo_signed +% product;
        const sum_bits: u64 = @bitCast(sum);
        state.hi = @bitCast(@as(u32, @intCast((sum_bits >> 32) & 0xFFFF_FFFF)));
        state.lo = @bitCast(@as(u32, @intCast(sum_bits & 0xFFFF_FFFF)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "maddu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const product: u64 = @as(u64, @intCast(@as(u32, @bitCast(u.read_reg(state, rs))))) *
            @as(u64, @intCast(@as(u32, @bitCast(u.read_reg(state, rt)))));
        const hi_bits: u32 = @bitCast(state.hi);
        const lo_bits: u32 = @bitCast(state.lo);
        const hilo: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
        const sum = hilo +% product;
        state.hi = @bitCast(@as(u32, @intCast((sum >> 32) & 0xFFFF_FFFF)));
        state.lo = @bitCast(@as(u32, @intCast(sum & 0xFFFF_FFFF)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "msub")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const product: i64 = @as(i64, u.read_reg(state, rs)) * @as(i64, u.read_reg(state, rt));
        const hi_bits: u32 = @bitCast(state.hi);
        const lo_bits: u32 = @bitCast(state.lo);
        const hilo_bits: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
        const hilo_signed: i64 = @bitCast(hilo_bits);
        const sum = hilo_signed -% product;
        const sum_bits: u64 = @bitCast(sum);
        state.hi = @bitCast(@as(u32, @intCast((sum_bits >> 32) & 0xFFFF_FFFF)));
        state.lo = @bitCast(@as(u32, @intCast(sum_bits & 0xFFFF_FFFF)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "msubu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const product: u64 = @as(u64, @intCast(@as(u32, @bitCast(u.read_reg(state, rs))))) *
            @as(u64, @intCast(@as(u32, @bitCast(u.read_reg(state, rt)))));
        const hi_bits: u32 = @bitCast(state.hi);
        const lo_bits: u32 = @bitCast(state.lo);
        const hilo: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
        const sum = hilo -% product;
        state.hi = @bitCast(@as(u32, @intCast((sum >> 32) & 0xFFFF_FFFF)));
        state.lo = @bitCast(@as(u32, @intCast(sum & 0xFFFF_FFFF)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "div")) {
        if (instruction.operand_count == 2) {
            const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
            const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            const divisor = u.read_reg(state, rt);
            if (divisor == 0) return .ok;
            const dividend = u.read_reg(state, rs);
            state.lo = @divTrunc(dividend, divisor);
            state.hi = @rem(dividend, divisor);
            return .ok;
        }
        if (instruction.operand_count == 3) {
            // Pseudo-op alias. MARS traps on register zero-divisor form, but
            // immediate form expands to raw `div` and therefore keeps HI/LO
            // unchanged on zero divisor.
            const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            const rhs_operand = u.instruction_operand(instruction, 2);
            if (u.delay_slot_active(state)) {
                // Register form first word is `bne rhs, $zero, ...`; no register/HI/LO writes.
                if (u.parse_register(rhs_operand) != null) return .ok;
                // Immediate forms begin with `$at` load in the first expanded word.
                if (u.parse_immediate(rhs_operand)) |imm| {
                    u.delay_slot_first_word_set_at_from_immediate(state, imm);
                    return .ok;
                }
            }
            if (u.parse_register(rhs_operand)) |rt| {
                const divisor = u.read_reg(state, rt);
                if (divisor == 0) return .runtime_error;
                const dividend = u.read_reg(state, rs);
                state.lo = @divTrunc(dividend, divisor);
                state.hi = @rem(dividend, divisor);
                u.write_reg(state, rd, state.lo);
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                if (imm != 0) {
                    const dividend = u.read_reg(state, rs);
                    state.lo = @divTrunc(dividend, imm);
                    state.hi = @rem(dividend, imm);
                }
                u.write_reg(state, rd, state.lo);
                return .ok;
            }
            return .parse_error;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "divu")) {
        if (instruction.operand_count == 2) {
            const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
            const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            const divisor: u32 = @bitCast(u.read_reg(state, rt));
            if (divisor == 0) return .ok;
            const dividend: u32 = @bitCast(u.read_reg(state, rs));
            state.lo = @bitCast(dividend / divisor);
            state.hi = @bitCast(dividend % divisor);
            return .ok;
        }
        if (instruction.operand_count == 3) {
            // Pseudo-op alias with register-form zero-divisor trap semantics.
            const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            const rhs_operand = u.instruction_operand(instruction, 2);
            if (u.delay_slot_active(state)) {
                // Register form first word is `bne rhs, $zero, ...`; no register/HI/LO writes.
                if (u.parse_register(rhs_operand) != null) return .ok;
                // Immediate forms begin with `$at` load in the first expanded word.
                if (u.parse_immediate(rhs_operand)) |imm| {
                    u.delay_slot_first_word_set_at_from_immediate(state, imm);
                    return .ok;
                }
            }
            if (u.parse_register(rhs_operand)) |rt| {
                const divisor: u32 = @bitCast(u.read_reg(state, rt));
                if (divisor == 0) return .runtime_error;
                const dividend: u32 = @bitCast(u.read_reg(state, rs));
                state.lo = @bitCast(dividend / divisor);
                state.hi = @bitCast(dividend % divisor);
                u.write_reg(state, rd, state.lo);
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                const divisor: u32 = @bitCast(imm);
                if (divisor != 0) {
                    const dividend: u32 = @bitCast(u.read_reg(state, rs));
                    state.lo = @bitCast(dividend / divisor);
                    state.hi = @bitCast(dividend % divisor);
                }
                u.write_reg(state, rd, state.lo);
                return .ok;
            }
            return .parse_error;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "rem")) {
        // Pseudo-op alias. Mirrors MARS expansion through `div` + `mfhi`.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // Register form first word is `bne rhs, $zero, ...`; no register/HI/LO writes.
            if (u.parse_register(rhs_operand) != null) return .ok;
            // Immediate forms begin with `$at` load in the first expanded word.
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
        }
        if (u.parse_register(rhs_operand)) |rt| {
            const divisor = u.read_reg(state, rt);
            if (divisor == 0) return .runtime_error;
            const dividend = u.read_reg(state, rs);
            state.lo = @divTrunc(dividend, divisor);
            state.hi = @rem(dividend, divisor);
            u.write_reg(state, rd, state.hi);
            return .ok;
        }
        if (u.parse_immediate(rhs_operand)) |imm| {
            if (imm != 0) {
                const dividend = u.read_reg(state, rs);
                state.lo = @divTrunc(dividend, imm);
                state.hi = @rem(dividend, imm);
            }
            u.write_reg(state, rd, state.hi);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "remu")) {
        // Pseudo-op alias. Mirrors MARS expansion through `divu` + `mfhi`.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // Register form first word is `bne rhs, $zero, ...`; no register/HI/LO writes.
            if (u.parse_register(rhs_operand) != null) return .ok;
            // Immediate forms begin with `$at` load in the first expanded word.
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
        }
        if (u.parse_register(rhs_operand)) |rt| {
            const divisor: u32 = @bitCast(u.read_reg(state, rt));
            if (divisor == 0) return .runtime_error;
            const dividend: u32 = @bitCast(u.read_reg(state, rs));
            state.lo = @bitCast(dividend / divisor);
            state.hi = @bitCast(dividend % divisor);
            u.write_reg(state, rd, state.hi);
            return .ok;
        }
        if (u.parse_immediate(rhs_operand)) |imm| {
            const divisor: u32 = @bitCast(imm);
            if (divisor != 0) {
                const dividend: u32 = @bitCast(u.read_reg(state, rs));
                state.lo = @bitCast(dividend / divisor);
                state.hi = @bitCast(dividend % divisor);
            }
            u.write_reg(state, rd, state.hi);
            return .ok;
        }
        return .parse_error;
    }

    return null;
}
