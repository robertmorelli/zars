const std = @import("std");

pub fn parse_signed_imm16(text: []const u8) ?i32 {
    // MIPS sign-extends the low 16 bits of immediate operands for this class.
    const imm = parse_immediate(text) orelse return null;
    const imm_bits: u32 = @bitCast(imm);
    const imm16: u16 = @intCast(imm_bits & 0xFFFF);
    const sign_extended: i16 = @bitCast(imm16);
    return sign_extended;
}

pub fn parse_imm16_bits(text: []const u8) ?u32 {
    // Logical immediate forms use zero-extended low 16 bits.
    const imm = parse_immediate(text) orelse return null;
    const imm_bits: u32 = @bitCast(imm);
    return imm_bits & 0x0000_FFFF;
}

pub fn parse_immediate(text: []const u8) ?i32 {
    // Support decimal and hex forms used by MARS fixtures.
    if (text.len == 0) return null;

    if (std.mem.startsWith(u8, text, "-0x") or std.mem.startsWith(u8, text, "-0X")) {
        const value = std.fmt.parseInt(i64, text[3..], 16) catch return null;
        return @intCast(-value);
    }

    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) {
        const value = std.fmt.parseInt(u32, text[2..], 16) catch return null;
        return @bitCast(value);
    }

    return std.fmt.parseInt(i32, text, 10) catch null;
}

pub fn parse_register(text: []const u8) ?u5 {
    if (text.len < 2) return null;
    if (text[0] != '$') return null;

    const name = text[1..];

    if (std.mem.eql(u8, name, "zero")) return 0;
    if (std.mem.eql(u8, name, "at")) return 1;
    if (std.mem.eql(u8, name, "v0")) return 2;
    if (std.mem.eql(u8, name, "v1")) return 3;
    if (std.mem.eql(u8, name, "a0")) return 4;
    if (std.mem.eql(u8, name, "a1")) return 5;
    if (std.mem.eql(u8, name, "a2")) return 6;
    if (std.mem.eql(u8, name, "a3")) return 7;
    if (std.mem.eql(u8, name, "t0")) return 8;
    if (std.mem.eql(u8, name, "t1")) return 9;
    if (std.mem.eql(u8, name, "t2")) return 10;
    if (std.mem.eql(u8, name, "t3")) return 11;
    if (std.mem.eql(u8, name, "t4")) return 12;
    if (std.mem.eql(u8, name, "t5")) return 13;
    if (std.mem.eql(u8, name, "t6")) return 14;
    if (std.mem.eql(u8, name, "t7")) return 15;
    if (std.mem.eql(u8, name, "s0")) return 16;
    if (std.mem.eql(u8, name, "s1")) return 17;
    if (std.mem.eql(u8, name, "s2")) return 18;
    if (std.mem.eql(u8, name, "s3")) return 19;
    if (std.mem.eql(u8, name, "s4")) return 20;
    if (std.mem.eql(u8, name, "s5")) return 21;
    if (std.mem.eql(u8, name, "s6")) return 22;
    if (std.mem.eql(u8, name, "s7")) return 23;
    if (std.mem.eql(u8, name, "t8")) return 24;
    if (std.mem.eql(u8, name, "t9")) return 25;
    if (std.mem.eql(u8, name, "k0")) return 26;
    if (std.mem.eql(u8, name, "k1")) return 27;
    if (std.mem.eql(u8, name, "gp")) return 28;
    if (std.mem.eql(u8, name, "sp")) return 29;
    if (std.mem.eql(u8, name, "fp") or std.mem.eql(u8, name, "s8")) return 30;
    if (std.mem.eql(u8, name, "ra")) return 31;

    // Fallback to numeric register names like `$8`.
    const numeric = std.fmt.parseInt(u8, name, 10) catch return null;
    if (numeric > 31) return null;
    return @intCast(numeric);
}

pub fn parse_fp_register(text: []const u8) ?u5 {
    if (text.len < 3) return null;
    if (text[0] != '$') return null;
    if (text[1] != 'f') return null;

    const numeric = std.fmt.parseInt(u8, text[2..], 10) catch return null;
    if (numeric > 31) return null;
    return @intCast(numeric);
}

pub fn parse_condition_flag(text: []const u8) ?u3 {
    const imm = parse_immediate(text) orelse return null;
    if (imm < 0 or imm > 7) return null;
    return @intCast(imm);
}

pub fn trim_ascii(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}
