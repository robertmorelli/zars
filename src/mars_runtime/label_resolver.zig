const std = @import("std");
const types = @import("types.zig");

const Program = types.Program;
const text_base_addr = types.text_base_addr;
const data_base_addr = types.data_base_addr;
const max_token_len = types.max_token_len;
const Fixup = types.Fixup;
const FixupKind = types.FixupKind;
const bits_per_halfword = types.bits_per_halfword;
const mask_u16 = types.mask_u16;

const operand_parse = @import("operand_parse.zig");

/// Find a text label by name, returns instruction index if found.
pub fn find_label(parsed: *Program, label_name: []const u8) ?u32 {
    var i: u32 = 0;
    while (i < parsed.label_count) : (i += 1) {
        const label = parsed.labels[i];
        if (std.mem.eql(u8, label.name[0..label.len], label_name)) {
            return label.instruction_index;
        }
    }
    return null;
}

/// Find a data label by name, returns data offset if found.
pub fn find_data_label(parsed: *Program, label_name: []const u8) ?u32 {
    var i: u32 = 0;
    while (i < parsed.data_label_count) : (i += 1) {
        const label = parsed.data_labels[i];
        if (std.mem.eql(u8, label.name[0..label.len], label_name)) {
            return label.instruction_index;
        }
    }
    return null;
}

/// Resolve a label to its absolute memory address (text or data).
pub fn resolve_label_address(parsed: *Program, label_name: []const u8) ?u32 {
    if (find_data_label(parsed, label_name)) |data_offset| {
        return data_base_addr + data_offset;
    }
    if (find_label(parsed, label_name)) |instruction_index| {
        const word_index = if (instruction_index < parsed.instruction_count)
            parsed.instruction_word_indices[instruction_index]
        else if (instruction_index == parsed.instruction_count)
            parsed.text_word_count
        else
            return null;
        return text_base_addr + word_index * 4;
    }
    return null;
}

/// Register a fixup for a label reference that needs to be patched.
pub fn add_fixup(
    parsed: *Program,
    label_name: []const u8,
    offset: i32,
    instruction_index: u32,
    operand_index: u8,
    kind: FixupKind,
) bool {
    if (parsed.fixup_count >= types.max_fixup_count) return false;
    if (label_name.len > max_token_len) return false;

    const fixup = &parsed.fixups[parsed.fixup_count];
    @memset(fixup.label_name[0..], 0);
    std.mem.copyForwards(u8, fixup.label_name[0..label_name.len], label_name);
    fixup.label_len = @intCast(label_name.len);
    fixup.offset = offset;
    fixup.instruction_index = instruction_index;
    fixup.operand_index = operand_index;
    fixup.kind = kind;
    parsed.fixup_count += 1;
    return true;
}

fn compute_hi_no_carry(value: u32) u32 {
    return (value >> bits_per_halfword) & mask_u16;
}

fn compute_hi_with_carry(value: u32) u32 {
    return ((value + 0x8000) >> bits_per_halfword) & mask_u16;
}

fn compute_lo_unsigned(value: u32) u32 {
    return value & mask_u16;
}

fn compute_lo_signed(value: u32) i32 {
    const lo_bits: u16 = @intCast(value & mask_u16);
    const lo_signed: i16 = @bitCast(lo_bits);
    return lo_signed;
}

/// Resolve all fixups by patching label references with computed addresses.
pub fn resolve_fixups(parsed: *Program) bool {
    var fixup_index: u32 = 0;
    while (fixup_index < parsed.fixup_count) : (fixup_index += 1) {
        const fixup = parsed.fixups[fixup_index];
        const label_name = fixup.label_name[0..fixup.label_len];
        const label_address = resolve_label_address(parsed, label_name) orelse return false;
        const address = label_address +% @as(u32, @bitCast(fixup.offset));

        var value_buffer: [32]u8 = undefined;
        const operand_text = switch (fixup.kind) {
            .hi_no_carry => blk: {
                const imm = compute_hi_no_carry(address);
                break :blk std.fmt.bufPrint(&value_buffer, "{}", .{imm}) catch return false;
            },
            .hi_with_carry => blk: {
                const imm = compute_hi_with_carry(address);
                break :blk std.fmt.bufPrint(&value_buffer, "{}", .{imm}) catch return false;
            },
            .lo_unsigned => blk: {
                const imm = compute_lo_unsigned(address);
                break :blk std.fmt.bufPrint(&value_buffer, "{}", .{imm}) catch return false;
            },
            .lo_signed => blk: {
                const imm = compute_lo_signed(address);
                break :blk std.fmt.bufPrint(&value_buffer, "{}", .{imm}) catch return false;
            },
        };

        const instruction = &parsed.instructions[fixup.instruction_index];
        if (fixup.operand_index >= instruction.operand_count) return false;
        if (operand_text.len > max_token_len) return false;
        @memset(instruction.operands[fixup.operand_index][0..], 0);
        std.mem.copyForwards(
            u8,
            instruction.operands[fixup.operand_index][0..operand_text.len],
            operand_text,
        );
        instruction.operand_lens[fixup.operand_index] = @intCast(operand_text.len);
    }
    return true;
}
