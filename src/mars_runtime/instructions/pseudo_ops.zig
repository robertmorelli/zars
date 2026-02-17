// Instruction group: Pseudo-instruction operations
// Handles li, la, move pseudo-ops.

const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    if (std.mem.eql(u8, op, "li")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = u.parse_immediate(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.delay_slot_active(state)) {
            if (!u.immediate_fits_signed_16(imm) and !u.immediate_fits_unsigned_16(imm)) {
                u.delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
        }
        u.write_reg(state, rd, imm);
        return .ok;
    }

    if (std.mem.eql(u8, op, "move")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        u.write_reg(state, rd, u.read_reg(state, rs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "la")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        if (u.delay_slot_active(state)) {
            const address_operand = u.parse_address_operand(u.instruction_operand(instruction, 1)) orelse return .parse_error;
            switch (address_operand.expression) {
                .empty => {
                    const base_register = address_operand.base_register orelse return .parse_error;
                    u.write_reg(state, rd, u.read_reg(state, base_register));
                    return .ok;
                },
                .immediate => |imm| {
                    if (address_operand.base_register == null) {
                        if (u.immediate_fits_signed_16(imm) or u.immediate_fits_unsigned_16(imm)) {
                            u.write_reg(state, rd, imm);
                            return .ok;
                        }
                        const imm_bits: u32 = @bitCast(imm);
                        const high_only: u32 = imm_bits & 0xFFFF_0000;
                        u.write_reg(state, 1, @bitCast(high_only));
                        return .ok;
                    }
                    if (u.immediate_fits_unsigned_16(imm)) {
                        u.write_reg(state, 1, imm);
                        return .ok;
                    }
                    const imm_bits: u32 = @bitCast(imm);
                    const high_only: u32 = imm_bits & 0xFFFF_0000;
                    u.write_reg(state, 1, @bitCast(high_only));
                    return .ok;
                },
                .label => |label_name| {
                    const label_address = u.resolve_label_address(parsed, label_name) orelse return .parse_error;
                    if (address_operand.base_register == null) {
                        const label_i32: i32 = @bitCast(label_address);
                        if (u.immediate_fits_signed_16(label_i32)) {
                            u.write_reg(state, rd, label_i32);
                            return .ok;
                        }
                    } else {
                        const label_i32: i32 = @bitCast(label_address);
                        if (u.immediate_fits_signed_16(label_i32)) {
                            const base_register = address_operand.base_register.?;
                            const lhs = u.read_reg(state, base_register);
                            const sum = lhs +% label_i32;
                            if (u.signed_add_overflow(lhs, label_i32, sum)) return .runtime_error;
                            u.write_reg(state, rd, sum);
                            return .ok;
                        }
                    }
                    const high_only: u32 = label_address & 0xFFFF_0000;
                    u.write_reg(state, 1, @bitCast(high_only));
                    return .ok;
                },
                .label_plus_offset => |label_offset| {
                    const label_address = u.resolve_label_address(parsed, label_offset.label_name) orelse return .parse_error;
                    const full_address = label_address +% @as(u32, @bitCast(label_offset.offset));
                    const high_only: u32 = full_address & 0xFFFF_0000;
                    u.write_reg(state, 1, @bitCast(high_only));
                    return .ok;
                },
                .invalid => return .parse_error,
            }
        }
        const address = u.resolve_address_operand(
            parsed,
            state,
            u.instruction_operand(instruction, 1),
        ) orelse return .parse_error;
        u.write_reg(state, rd, @bitCast(address));
        return .ok;
    }

    if (std.mem.eql(u8, op, "nop")) {
        return .ok;
    }

    return null;
}
