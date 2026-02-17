const std = @import("std");
const u = @import("inst_util.zig");

pub fn execute(parsed: *u.Program, state: *u.ExecState, instruction: *const u.LineInstruction, op: []const u8) ?u.StatusCode {
    if (std.mem.eql(u8, op, "mfc0")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        u.write_reg(state, rt, state.cp0_regs[rd]);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mtc0")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = u.parse_register(u.instruction_operand(instruction, 0)) orelse return .parse_error;
        const rd = u.parse_register(u.instruction_operand(instruction, 1)) orelse return .parse_error;
        state.cp0_regs[rd] = u.read_reg(state, rt);
        return .ok;
    }

    if (std.mem.eql(u8, op, "eret")) {
        if (instruction.operand_count != 0) return .parse_error;
        // STATUS bit 1 is EXL in MARS.
        const status_bits: u32 = @bitCast(state.cp0_regs[12]);
        state.cp0_regs[12] = @bitCast(status_bits & ~@as(u32, 1 << 1));
        const epc_address: u32 = @bitCast(state.cp0_regs[14]);
        const target_index = u.text_address_to_instruction_index(parsed, epc_address) orelse return .runtime_error;
        state.pc = target_index;
        return .ok;
    }

    return null;
}
