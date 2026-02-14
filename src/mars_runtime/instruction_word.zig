const std = @import("std");
const assert = std.debug.assert;

pub const opcode_shift: u5 = 26;
pub const code_shift: u5 = 6;
pub const function_mask: u32 = 0x3F;
pub const code_mask: u32 = 0x000F_FFFF;

pub const syscall_function: u6 = 0x0C;
pub const j_opcode: u6 = 0x02;
pub const j_imm_mask: u32 = 0x03FF_FFFF;

pub const RFields = struct {
    opcode: u6,
    rs: u5,
    rt: u5,
    rd: u5,
    shamt: u5,
    funct: u6,
    code: u20,
};

pub fn decode_r_fields(word: u32) RFields {
    // Decode with explicit masks/shifts to mirror MIPS bit layout.
    const opcode: u6 = @intCast((word >> opcode_shift) & function_mask);
    const rs: u5 = @intCast((word >> 21) & 0x1F);
    const rt: u5 = @intCast((word >> 16) & 0x1F);
    const rd: u5 = @intCast((word >> 11) & 0x1F);
    const shamt: u5 = @intCast((word >> 6) & 0x1F);
    const funct: u6 = @intCast(word & function_mask);
    const code: u20 = @intCast((word >> code_shift) & code_mask);

    return .{
        .opcode = opcode,
        .rs = rs,
        .rt = rt,
        .rd = rd,
        .shamt = shamt,
        .funct = funct,
        .code = code,
    };
}

pub fn encode_syscall(code: u20) u32 {
    // Syscall is an R-format instruction with funct=0x0C.
    return (@as(u32, code) << code_shift) | syscall_function;
}

pub fn is_syscall(word: u32) bool {
    const fields = decode_r_fields(word);
    if (fields.opcode != 0) {
        return false;
    }
    return fields.funct == syscall_function;
}

pub fn encode_jump(target_word_index: u26) u32 {
    // Jump immediate stores instruction word index, not byte address.
    const opcode_bits: u32 = @as(u32, j_opcode) << opcode_shift;
    return opcode_bits | @as(u32, target_word_index);
}

pub fn decode_jump_target(word: u32) u26 {
    const opcode: u6 = @intCast((word >> opcode_shift) & function_mask);
    assert(opcode == j_opcode);
    return @intCast(word & j_imm_mask);
}

test "syscall code field survives decode" {
    const word = encode_syscall(0xABCDE);
    const fields = decode_r_fields(word);

    try std.testing.expect(is_syscall(word));
    try std.testing.expectEqual(@as(u20, 0xABCDE), fields.code);
}

test "jump encoding matches MARS masks" {
    const encoded = encode_jump(0x0123_456);

    try std.testing.expectEqual(@as(u32, 0x0812_3456), encoded);
    try std.testing.expectEqual(@as(u26, 0x0123_456), decode_jump_target(encoded));
}
