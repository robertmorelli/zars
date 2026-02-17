const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    if (std.mem.eql(u8, op, "j")) {
        if (instruction.operand_count != 1) return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 0)) orelse return .parse_error;
        u.process_jump_instruction(state, target);
        return .ok;
    }

    if (std.mem.eql(u8, op, "b")) {
        // Pseudo-op alias for unconditional branch.
        if (instruction.operand_count != 1) return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 0)) orelse return .parse_error;
        u.process_branch_instruction(state, target);
        return .ok;
    }

    if (std.mem.eql(u8, op, "bc1t")) {
        if (instruction.operand_count != 1 and instruction.operand_count != 2) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 2)
            u.parse_condition_flag(u.instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const target_operand_index: u8 = if (instruction.operand_count == 2) 1 else 0;
        const target = u.find_label(parsed, u.instruction_operand(instruction, target_operand_index)) orelse return .parse_error;
        if (u.get_fp_condition_flag(state, cc)) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bc1f")) {
        if (instruction.operand_count != 1 and instruction.operand_count != 2) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 2)
            u.parse_condition_flag(u.instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const target_operand_index: u8 = if (instruction.operand_count == 2) 1 else 0;
        const target = u.find_label(parsed, u.instruction_operand(instruction, target_operand_index)) orelse return .parse_error;
        if (!u.get_fp_condition_flag(state, cc)) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "blt")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.read_reg(state, rs) < u.read_reg(state, rt)) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bge")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.read_reg(state, rs) >= u.read_reg(state, rt)) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgt")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.read_reg(state, rs) > u.read_reg(state, rt)) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "ble")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.read_reg(state, rs) <= u.read_reg(state, rt)) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bltu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        if (lhs < rhs) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgeu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        if (lhs >= rhs) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgtu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        if (lhs > rhs) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bleu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(u.read_reg(state, rs));
        const rhs: u32 = @bitCast(u.read_reg(state, rt));
        if (lhs <= rhs) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "beq")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.read_reg(state, rs) == u.read_reg(state, rt)) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bne")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.read_reg(state, rs) != u.read_reg(state, rt)) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "beqz")) {
        // Pseudo-op alias for `beq $rs, $zero, label`.
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) == 0) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bnez")) {
        // Pseudo-op alias for `bne $rs, $zero, label`.
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) != 0) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgez")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) >= 0) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgezal")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) >= 0) {
            u.process_return_address(parsed, state, 31);
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgtz")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) > 0) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "blez")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) <= 0) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bltz")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) < 0) {
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bltzal")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (u.read_reg(state, rs) < 0) {
            u.process_return_address(parsed, state, 31);
            u.process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "jal")) {
        if (instruction.operand_count != 1) return .parse_error;
        const target = u.find_label(parsed, u.instruction_operand(instruction, 0)) orelse return .parse_error;
        u.process_return_address(parsed, state, 31);
        u.process_jump_instruction(state, target);
        return .ok;
    }

    if (std.mem.eql(u8, op, "jr")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rs = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const target_addr: u32 = @bitCast(u.read_reg(state, rs));
        const target_index = u.text_address_to_instruction_index(parsed, target_addr) orelse return .runtime_error;
        u.process_jump_instruction(state, target_index);
        return .ok;
    }

    if (std.mem.eql(u8, op, "jalr")) {
        if (instruction.operand_count != 1 and instruction.operand_count != 2) return .parse_error;
        const rd: u5 = if (instruction.operand_count == 2)
            u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error
        else
            31;
        const rs_operand_index: u8 = if (instruction.operand_count == 2) 1 else 0;
        const rs = u.parse_register(u.instruction_operand(instruction, rs_operand_index)) orelse return .parse_error;
        const target_addr: u32 = @bitCast(u.read_reg(state, rs));
        const target_index = u.text_address_to_instruction_index(parsed, target_addr) orelse return .runtime_error;
        u.process_return_address(parsed, state, rd);
        u.process_jump_instruction(state, target_index);
        return .ok;
    }

    return null;
}
