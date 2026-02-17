const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    _ = parsed;

    if (std.mem.eql(u8, op, "mov.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        u.write_fp_single(state, fd, u.read_fp_single(state, fs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mov.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        u.write_fp_single(state, fd, u.read_fp_single(state, fs));
        u.write_fp_single(state, fd + 1, u.read_fp_single(state, fs + 1));
        return .ok;
    }

    if (std.mem.eql(u8, op, "movf.s")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (!u.get_fp_condition_flag(state, cc)) {
            u.write_fp_single(state, fd, u.read_fp_single(state, fs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movf.d")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (!u.get_fp_condition_flag(state, cc)) {
            u.write_fp_single(state, fd, u.read_fp_single(state, fs));
            u.write_fp_single(state, fd + 1, u.read_fp_single(state, fs + 1));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movt.s")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (u.get_fp_condition_flag(state, cc)) {
            u.write_fp_single(state, fd, u.read_fp_single(state, fs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movt.d")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        const cc: u3 = if (instruction.operand_count == 3)
            u.parse_condition_flag(u.instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (u.get_fp_condition_flag(state, cc)) {
            u.write_fp_single(state, fd, u.read_fp_single(state, fs));
            u.write_fp_single(state, fd + 1, u.read_fp_single(state, fs + 1));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movn.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.read_reg(state, rt) != 0) {
            u.write_fp_single(state, fd, u.read_fp_single(state, fs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movn.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (u.read_reg(state, rt) != 0) {
            u.write_fp_single(state, fd, u.read_fp_single(state, fs));
            u.write_fp_single(state, fd + 1, u.read_fp_single(state, fs + 1));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movz.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (u.read_reg(state, rt) == 0) {
            u.write_fp_single(state, fd, u.read_fp_single(state, fs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movz.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = u.parse_fp_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (u.read_reg(state, rt) == 0) {
            u.write_fp_single(state, fd, u.read_fp_single(state, fs));
            u.write_fp_single(state, fd + 1, u.read_fp_single(state, fs + 1));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "mfc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        u.write_reg(state, rt, @bitCast(u.read_fp_single(state, fs)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mfc1.d")) {
        // Double transfer pseudo-op into register pair (rt, rt+1).
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (rt >= 31) return .runtime_error;
        if (u.delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word: `mfc1 rt, fs`.
            u.write_reg(state, rt, @bitCast(u.read_fp_single(state, fs)));
            return .ok;
        }
        u.write_reg(state, rt, @bitCast(u.read_fp_single(state, fs)));
        u.write_reg(state, rt + 1, @bitCast(u.read_fp_single(state, fs + 1)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mtc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        u.write_fp_single(state, fs, @bitCast(u.read_reg(state, rt)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mtc1.d")) {
        // Double transfer pseudo-op from register pair (rt, rt+1).
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = u.parse_fp_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!u.fp_double_register_pair_valid(fs)) return .runtime_error;
        if (rt >= 31) return .runtime_error;
        if (u.delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word: `mtc1 rt, fs`.
            u.write_fp_single(state, fs, @bitCast(u.read_reg(state, rt)));
            return .ok;
        }
        u.write_fp_single(state, fs, @bitCast(u.read_reg(state, rt)));
        u.write_fp_single(state, fs + 1, @bitCast(u.read_reg(state, rt + 1)));
        return .ok;
    }

    return null;
}
