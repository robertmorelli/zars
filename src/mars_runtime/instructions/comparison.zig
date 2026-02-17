const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    if (std.mem.eql(u8, op, "slt")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        u.write_reg(state, rd, if (u.read_reg(state, rs) < u.read_reg(state, rt)) 1 else 0);
        return .ok;
    }

    if (std.mem.eql(u8, op, "sltu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        u.write_reg(state, rd, if (lhs < rhs) 1 else 0);
        return .ok;
    }

    if (std.mem.eql(u8, op, "slti")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = u.parse_signed_imm16(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        u.write_reg(state, rt, if (u.read_reg(state, rs) < imm) 1 else 0);
        return .ok;
    }

    if (std.mem.eql(u8, op, "sltiu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = u.parse_signed_imm16(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(imm);
        u.write_reg(state, rt, if (lhs < rhs) 1 else 0);
        return .ok;
    }

    if (std.mem.eql(u8, op, "seq")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // `seq` first expansion word is `subu rd, rs, rhs`.
            if (u.parse_register(rhs_operand)) |rt| {
                u.write_reg(state, rd, u.read_reg(state, rs) -% u.read_reg(state, rt));
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (u.parse_register(rhs_operand)) |rt| {
            u.write_reg(state, rd, if (u.read_reg(state, rs) == u.read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (u.parse_immediate(rhs_operand)) |imm| {
            u.write_reg(state, rd, if (u.read_reg(state, rs) == imm) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sne")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // `sne` first expansion word is `subu rd, rs, rhs`.
            if (u.parse_register(rhs_operand)) |rt| {
                u.write_reg(state, rd, u.read_reg(state, rs) -% u.read_reg(state, rt));
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (u.parse_register(rhs_operand)) |rt| {
            u.write_reg(state, rd, if (u.read_reg(state, rs) != u.read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (u.parse_immediate(rhs_operand)) |imm| {
            u.write_reg(state, rd, if (u.read_reg(state, rs) != imm) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sge")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // `sge` first expansion word is `slt rd, rs, rhs`.
            if (u.parse_register(rhs_operand)) |rt| {
                u.write_reg(state, rd, if (u.read_reg(state, rs) < u.read_reg(state, rt)) 1 else 0);
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (u.parse_register(rhs_operand)) |rt| {
            u.write_reg(state, rd, if (u.read_reg(state, rs) >= u.read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (u.parse_immediate(rhs_operand)) |imm| {
            u.write_reg(state, rd, if (u.read_reg(state, rs) >= imm) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sgt")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // `sgt` register form is single-word `slt rd, rhs, rs`; immediate forms start with `$at` load.
            if (u.parse_register(rhs_operand)) |rt| {
                u.write_reg(state, rd, if (u.read_reg(state, rt) < u.read_reg(state, rs)) 1 else 0);
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (u.parse_register(rhs_operand)) |rt| {
            u.write_reg(state, rd, if (u.read_reg(state, rs) > u.read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (u.parse_immediate(rhs_operand)) |imm| {
            u.write_reg(state, rd, if (u.read_reg(state, rs) > imm) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sle")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // `sle` first expansion word is `slt rd, rhs, rs`.
            if (u.parse_register(rhs_operand)) |rt| {
                u.write_reg(state, rd, if (u.read_reg(state, rt) < u.read_reg(state, rs)) 1 else 0);
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (u.parse_register(rhs_operand)) |rt| {
            u.write_reg(state, rd, if (u.read_reg(state, rs) <= u.read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (u.parse_immediate(rhs_operand)) |imm| {
            u.write_reg(state, rd, if (u.read_reg(state, rs) <= imm) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sgeu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // `sgeu` first expansion word is `sltu rd, rs, rhs`.
            if (u.parse_register(rhs_operand)) |rt| {
                const rhs: u32 = @bitCast(u.read_reg(state, rt));
                u.write_reg(state, rd, if (lhs < rhs) 1 else 0);
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (u.parse_register(rhs_operand)) |rt| {
            const rhs: u32 = @bitCast(u.read_reg(state, rt));
            u.write_reg(state, rd, if (lhs >= rhs) 1 else 0);
            return .ok;
        }
        if (u.parse_immediate(rhs_operand)) |imm| {
            const rhs: u32 = @bitCast(imm);
            u.write_reg(state, rd, if (lhs >= rhs) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sgtu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // `sgtu` register form is single-word `sltu rd, rhs, rs`; immediate forms start with `$at` load.
            if (u.parse_register(rhs_operand)) |rt| {
                const rhs: u32 = @bitCast(u.read_reg(state, rt));
                u.write_reg(state, rd, if (rhs < lhs) 1 else 0);
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (u.parse_register(rhs_operand)) |rt| {
            const rhs: u32 = @bitCast(u.read_reg(state, rt));
            u.write_reg(state, rd, if (lhs > rhs) 1 else 0);
            return .ok;
        }
        if (u.parse_immediate(rhs_operand)) |imm| {
            const rhs: u32 = @bitCast(imm);
            u.write_reg(state, rd, if (lhs > rhs) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sleu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs_operand = u.instruction_operand(instruction, 2);
        if (u.delay_slot_active(state)) {
            // `sleu` first expansion word is `sltu rd, rhs, rs`.
            if (u.parse_register(rhs_operand)) |rt| {
                const rhs: u32 = @bitCast(u.read_reg(state, rt));
                u.write_reg(state, rd, if (rhs < lhs) 1 else 0);
                return .ok;
            }
            if (u.parse_immediate(rhs_operand)) |imm| {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (u.parse_register(rhs_operand)) |rt| {
            const rhs: u32 = @bitCast(u.read_reg(state, rt));
            u.write_reg(state, rd, if (lhs <= rhs) 1 else 0);
            return .ok;
        }
        if (u.parse_immediate(rhs_operand)) |imm| {
            const rhs: u32 = @bitCast(imm);
            u.write_reg(state, rd, if (lhs <= rhs) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    return null;
}
