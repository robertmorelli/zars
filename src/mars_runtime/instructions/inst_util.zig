// Shared instruction utilities and helpers.
// Common functions used across all instruction group modules.
// All functions take explicit parameters (no module-level globals).

const std = @import("std");
const model = @import("../model.zig");
const operand_parse = @import("../operand_parse.zig");
pub const fp_math = @import("../fp_math.zig");
pub const output_format = @import("../output_format.zig");
pub const java_random = @import("../java_random.zig");

pub const Program = model.Program;
pub const ExecState = model.ExecState;
pub const LineInstruction = model.LineInstruction;
pub const StatusCode = model.StatusCode;
pub const DelayedBranchState = model.DelayedBranchState;

pub const text_base_addr = model.text_base_addr;
pub const data_base_addr = model.data_base_addr;
pub const heap_base_addr = model.heap_base_addr;
pub const heap_capacity_bytes = model.heap_capacity_bytes;
pub const max_instruction_count = model.max_instruction_count;
pub const max_open_file_count = model.max_open_file_count;
pub const max_virtual_file_count = model.max_virtual_file_count;
pub const virtual_file_name_capacity_bytes = model.virtual_file_name_capacity_bytes;
pub const virtual_file_data_capacity_bytes = model.virtual_file_data_capacity_bytes;
pub const max_random_stream_count = model.max_random_stream_count;
pub const VirtualFile = model.VirtualFile;
pub const OpenFile = model.OpenFile;

// Re-export operand parsing for convenience.
pub const parse_register = operand_parse.parse_register;
pub const parse_fp_register = operand_parse.parse_fp_register;
pub const parse_immediate = operand_parse.parse_immediate;
pub const parse_signed_imm16 = operand_parse.parse_signed_imm16;
pub const parse_imm16_bits = operand_parse.parse_imm16_bits;
pub const parse_condition_flag = operand_parse.parse_condition_flag;

// Centralized constants matching engine.zig.
pub const reg_at: u5 = 1;
pub const mask_u16: u32 = 0xFFFF;
pub const mask_u32: u32 = 0xFFFF_FFFF;
pub const mask_shift_amount: u32 = 0x1F;
pub const bits_per_word: u32 = 32;
pub const bits_per_halfword: u32 = 16;

// =========================================================================
// Operand accessor
// =========================================================================

pub fn instruction_operand(instruction: *const LineInstruction, index: u8) []const u8 {
    return instruction.operands[index][0..instruction.operand_lens[index]];
}

// =========================================================================
// Integer register accessors
// =========================================================================

pub fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

pub fn write_reg(state: *ExecState, reg: u5, value: i32) void {
    if (reg == 0) return;
    state.regs[reg] = value;
}

// =========================================================================
// FP register accessors
// =========================================================================

pub fn read_fp_single(state: *ExecState, reg: u5) u32 {
    return state.fp_regs[reg];
}

pub fn write_fp_single(state: *ExecState, reg: u5, bits: u32) void {
    state.fp_regs[reg] = bits;
}

pub fn read_fp_double(state: *ExecState, reg: u5) u64 {
    const low_word = @as(u64, state.fp_regs[reg]);
    const high_word = @as(u64, state.fp_regs[reg + 1]);
    return (high_word << 32) | low_word;
}

pub fn write_fp_double(state: *ExecState, reg: u5, bits: u64) void {
    state.fp_regs[reg] = @intCast(bits & 0xFFFF_FFFF);
    state.fp_regs[reg + 1] = @intCast((bits >> 32) & 0xFFFF_FFFF);
}

pub fn fp_double_register_pair_valid(reg: u5) bool {
    if ((reg & 1) != 0) return false;
    return reg < 31;
}

pub fn set_fp_condition_flag(state: *ExecState, flag: u3, enabled: bool) void {
    const mask: u8 = @as(u8, 1) << flag;
    if (enabled) {
        state.fp_condition_flags |= mask;
    } else {
        state.fp_condition_flags &= ~mask;
    }
}

pub fn get_fp_condition_flag(state: *ExecState, flag: u3) bool {
    const mask: u8 = @as(u8, 1) << flag;
    return (state.fp_condition_flags & mask) != 0;
}

// =========================================================================
// Memory accessors (take explicit state for heap access)
// =========================================================================

pub fn data_address_to_offset(parsed: *Program, address: u32) ?u32 {
    if (address < data_base_addr) return null;
    const offset = address - data_base_addr;
    if (offset >= parsed.data_len_bytes) return null;
    return offset;
}

pub fn heap_address_to_offset(state: *ExecState, address: u32) ?u32 {
    if (address < heap_base_addr) return null;
    const offset = address - heap_base_addr;
    if (offset >= state.heap_len_bytes) return null;
    return offset;
}

pub fn read_u8(parsed: *Program, state: *ExecState, address: u32) ?u8 {
    if (data_address_to_offset(parsed, address)) |offset| {
        return parsed.data[offset];
    }
    if (heap_address_to_offset(state, address)) |offset| {
        return state.heap[offset];
    }
    return null;
}

pub fn write_u8(parsed: *Program, state: *ExecState, address: u32, value: u8) bool {
    if (data_address_to_offset(parsed, address)) |offset| {
        parsed.data[offset] = value;
        return true;
    }
    if (heap_address_to_offset(state, address)) |offset| {
        state.heap[offset] = value;
        return true;
    }
    return false;
}

pub fn read_u16_be(parsed: *Program, state: *ExecState, address: u32) ?u16 {
    const b0 = read_u8(parsed, state, address) orelse return null;
    const b1 = read_u8(parsed, state, address + 1) orelse return null;
    return @as(u16, b0) | (@as(u16, b1) << 8);
}

pub fn write_u16_be(parsed: *Program, state: *ExecState, address: u32, value: u16) bool {
    return write_u8(parsed, state, address, @intCast(value & 0xFF)) and
        write_u8(parsed, state, address + 1, @intCast((value >> 8) & 0xFF));
}

pub fn read_u32_be(parsed: *Program, state: *ExecState, address: u32) ?u32 {
    const b0 = read_u8(parsed, state, address) orelse return null;
    const b1 = read_u8(parsed, state, address + 1) orelse return null;
    const b2 = read_u8(parsed, state, address + 2) orelse return null;
    const b3 = read_u8(parsed, state, address + 3) orelse return null;
    return @as(u32, b0) |
        (@as(u32, b1) << 8) |
        (@as(u32, b2) << 16) |
        (@as(u32, b3) << 24);
}

pub fn write_u32_be(parsed: *Program, state: *ExecState, address: u32, value: u32) bool {
    return write_u8(parsed, state, address, @intCast(value & 0xFF)) and
        write_u8(parsed, state, address + 1, @intCast((value >> 8) & 0xFF)) and
        write_u8(parsed, state, address + 2, @intCast((value >> 16) & 0xFF)) and
        write_u8(parsed, state, address + 3, @intCast((value >> 24) & 0xFF));
}

pub fn read_u64_be(parsed: *Program, state: *ExecState, address: u32) ?u64 {
    const b0 = read_u8(parsed, state, address + 0) orelse return null;
    const b1 = read_u8(parsed, state, address + 1) orelse return null;
    const b2 = read_u8(parsed, state, address + 2) orelse return null;
    const b3 = read_u8(parsed, state, address + 3) orelse return null;
    const b4 = read_u8(parsed, state, address + 4) orelse return null;
    const b5 = read_u8(parsed, state, address + 5) orelse return null;
    const b6 = read_u8(parsed, state, address + 6) orelse return null;
    const b7 = read_u8(parsed, state, address + 7) orelse return null;
    return @as(u64, b0) |
        (@as(u64, b1) << 8) |
        (@as(u64, b2) << 16) |
        (@as(u64, b3) << 24) |
        (@as(u64, b4) << 32) |
        (@as(u64, b5) << 40) |
        (@as(u64, b6) << 48) |
        (@as(u64, b7) << 56);
}

pub fn write_u32(parsed: *Program, state: *ExecState, address: u32, value: u32) bool {
    if (write_u32_be(parsed, state, address, value)) return true;
    return write_text_patch_word(parsed, state, address, value);
}

pub fn write_text_patch_word(parsed: *Program, state: *ExecState, address: u32, value: u32) bool {
    if (!state.smc_enabled) return false;
    const instruction_index = text_address_to_instruction_index(parsed, address) orelse return false;
    state.text_patch_words[instruction_index] = value;
    state.text_patch_valid[instruction_index] = true;
    return true;
}

// =========================================================================
// Label and address resolution
// =========================================================================

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

pub fn text_address_to_instruction_index(parsed: *Program, address: u32) ?u32 {
    if (address < text_base_addr) return null;
    const relative = address - text_base_addr;
    if ((relative & 3) != 0) return null;
    const word_index = relative / 4;
    if (word_index >= parsed.text_word_count) return null;
    if (!parsed.text_word_to_instruction_valid[word_index]) return null;
    return parsed.text_word_to_instruction_index[word_index];
}

pub fn instruction_index_to_text_address(parsed: *Program, instruction_index: u32) ?u32 {
    if (instruction_index <= parsed.instruction_count) {
        const word_index = if (instruction_index < parsed.instruction_count)
            parsed.instruction_word_indices[instruction_index]
        else
            parsed.text_word_count;
        return text_base_addr + word_index * 4;
    }
    return null;
}

pub const AddressExpression = union(enum) {
    empty,
    immediate: i32,
    label: []const u8,
    label_plus_offset: struct {
        label_name: []const u8,
        offset: i32,
    },
    invalid,
};

pub const AddressOperand = struct {
    base_register: ?u5,
    expression: AddressExpression,
};

pub fn parse_address_operand(operand_text: []const u8) ?AddressOperand {
    const trimmed = operand_parse.trim_ascii(operand_text);
    if (trimmed.len == 0) return null;

    const open_paren = std.mem.indexOfScalar(u8, trimmed, '(');
    if (open_paren == null) {
        return .{
            .base_register = null,
            .expression = parse_address_expression(trimmed),
        };
    }

    const open_index = open_paren.?;
    const close_paren = std.mem.indexOfScalarPos(u8, trimmed, open_index, ')') orelse return null;
    const trailing = operand_parse.trim_ascii(trimmed[close_paren + 1 ..]);
    if (trailing.len != 0) return null;
    if (close_paren <= open_index + 1) return null;

    const expression_text = operand_parse.trim_ascii(trimmed[0..open_index]);
    const base_text = operand_parse.trim_ascii(trimmed[open_index + 1 .. close_paren]);
    const base_register = operand_parse.parse_register(base_text) orelse return null;

    return .{
        .base_register = base_register,
        .expression = parse_address_expression(expression_text),
    };
}

pub fn parse_address_expression(expression_text: []const u8) AddressExpression {
    const trimmed = operand_parse.trim_ascii(expression_text);
    if (trimmed.len == 0) return .empty;

    if (operand_parse.parse_immediate(trimmed)) |imm| {
        return .{ .immediate = imm };
    }

    if (std.mem.indexOfScalarPos(u8, trimmed, 1, '+')) |op_index| {
        const label_text = operand_parse.trim_ascii(trimmed[0..op_index]);
        const offset_text = operand_parse.trim_ascii(trimmed[op_index + 1 ..]);
        if (label_text.len == 0) return .invalid;
        if (offset_text.len == 0) return .invalid;

        const offset_imm = operand_parse.parse_immediate(offset_text) orelse return .invalid;

        return .{
            .label_plus_offset = .{
                .label_name = label_text,
                .offset = offset_imm,
            },
        };
    }

    if (std.mem.indexOfScalarPos(u8, trimmed, 1, '-') != null) return .invalid;

    return .{ .label = trimmed };
}

pub fn resolve_address_operand(parsed: *Program, state: *ExecState, operand_text: []const u8) ?u32 {
    const address_operand = parse_address_operand(operand_text) orelse return null;

    var expression_address: u32 = 0;
    switch (address_operand.expression) {
        .empty => {
            if (address_operand.base_register == null) return null;
            expression_address = 0;
        },
        .immediate => |imm| {
            expression_address = @bitCast(imm);
        },
        .label => |label_name| {
            expression_address = resolve_label_address(parsed, label_name) orelse return null;
        },
        .label_plus_offset => |label_offset| {
            const label_address = resolve_label_address(parsed, label_offset.label_name) orelse return null;
            expression_address = label_address +% @as(u32, @bitCast(label_offset.offset));
        },
        .invalid => return null,
    }

    if (address_operand.base_register) |base_register| {
        const base_address: u32 = @bitCast(read_reg(state, base_register));
        return base_address +% expression_address;
    }

    return expression_address;
}

pub fn resolve_load_address(parsed: *Program, state: *ExecState, operand_text: []const u8) ?u32 {
    return resolve_address_operand(parsed, state, operand_text);
}

// =========================================================================
// Branch and jump helpers
// =========================================================================

pub fn process_branch_instruction(state: *ExecState, target_instruction_index: u32) void {
    if (state.delayed_branching_enabled) {
        delayed_branch_register(state, target_instruction_index);
    } else {
        state.pc = target_instruction_index;
    }
}

pub fn process_jump_instruction(state: *ExecState, target_instruction_index: u32) void {
    if (state.delayed_branching_enabled) {
        delayed_branch_register(state, target_instruction_index);
    } else {
        state.pc = target_instruction_index;
    }
}

pub fn delayed_branch_register(state: *ExecState, target_instruction_index: u32) void {
    switch (state.delayed_branch_state) {
        .cleared => {
            state.delayed_branch_target = target_instruction_index;
            state.delayed_branch_state = .registered;
        },
        .registered => {
            state.delayed_branch_state = .registered;
        },
        .triggered => {
            state.delayed_branch_state = .registered;
        },
    }
}

pub fn process_return_address(parsed: *Program, state: *ExecState, reg: u5) void {
    const target_instruction_index = if (state.delayed_branching_enabled)
        state.pc + 1
    else
        state.pc;
    const return_address = instruction_index_to_text_address(parsed, target_instruction_index) orelse text_base_addr;
    write_reg(state, reg, @bitCast(return_address));
}

// =========================================================================
// Overflow and immediate helpers
// =========================================================================

pub fn signed_add_overflow(lhs: i32, rhs: i32, sum: i32) bool {
    return (lhs >= 0 and rhs >= 0 and sum < 0) or (lhs < 0 and rhs < 0 and sum >= 0);
}

pub fn signed_sub_overflow(lhs: i32, rhs: i32, dif: i32) bool {
    return (lhs >= 0 and rhs < 0 and dif < 0) or (lhs < 0 and rhs >= 0 and dif >= 0);
}

pub fn delay_slot_active(state: *const ExecState) bool {
    return state.delayed_branch_state == .triggered;
}

pub fn immediate_fits_signed_16(imm: i32) bool {
    return imm >= -32768 and imm <= 32767;
}

pub fn immediate_fits_unsigned_16(imm: i32) bool {
    const u: u32 = @bitCast(imm);
    return u <= 65535;
}

pub fn load_at_high_bits_only(state: *ExecState, imm: i32) void {
    const imm_bits: u32 = @bitCast(imm);
    const high_only: u32 = imm_bits & 0xFFFF_0000;
    write_reg(state, reg_at, @bitCast(high_only));
}

pub fn delay_slot_first_word_set_at_from_immediate(state: *ExecState, imm: i32) void {
    if (immediate_fits_signed_16(imm)) {
        write_reg(state, reg_at, imm);
        return;
    }
    load_at_high_bits_only(state, imm);
}

// =========================================================================
// Bitwise operation helper
// =========================================================================

pub fn execute_bitwise_op(
    state: *ExecState,
    instruction: *const LineInstruction,
    comptime op_fn: fn (u32, u32) u32,
) StatusCode {
    if (instruction.operand_count == 3) {
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        if (parse_register(instruction_operand(instruction, 2))) |rt| {
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(op_fn(lhs, rhs)));
            return .ok;
        }
        const imm = parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (delay_slot_active(state)) {
            if (immediate_fits_unsigned_16(imm)) {
                const imm16: u32 = @intCast(imm);
                write_reg(state, rd, @bitCast(op_fn(lhs, imm16)));
                return .ok;
            }
            load_at_high_bits_only(state, imm);
            return .ok;
        }
        const rhs: u32 = if (immediate_fits_unsigned_16(imm))
            @intCast(imm)
        else
            @bitCast(imm);
        write_reg(state, rd, @bitCast(op_fn(lhs, rhs)));
        return .ok;
    }
    if (instruction.operand_count == 2) {
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rd));
        if (parse_register(instruction_operand(instruction, 1))) |rt| {
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(op_fn(lhs, rhs)));
            return .ok;
        }
        const imm = parse_immediate(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (delay_slot_active(state)) {
            if (immediate_fits_unsigned_16(imm)) {
                const imm16: u32 = @intCast(imm);
                write_reg(state, rd, @bitCast(op_fn(lhs, imm16)));
                return .ok;
            }
            load_at_high_bits_only(state, imm);
            return .ok;
        }
        const rhs: u32 = if (immediate_fits_unsigned_16(imm))
            @intCast(imm)
        else
            @bitCast(imm);
        write_reg(state, rd, @bitCast(op_fn(lhs, rhs)));
        return .ok;
    }
    return .parse_error;
}

pub fn bitwise_and(a: u32, b: u32) u32 {
    return a & b;
}

pub fn bitwise_or(a: u32, b: u32) u32 {
    return a | b;
}

pub fn bitwise_xor(a: u32, b: u32) u32 {
    return a ^ b;
}

// =========================================================================
// Syscall helpers (string reading, input, file ops)
// =========================================================================

pub fn append_c_string_from_data(
    parsed: *Program,
    _: *ExecState,
    data_offset: u32,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    if (data_offset >= parsed.data_len_bytes) return .runtime_error;
    var index: u32 = data_offset;
    while (index < parsed.data_len_bytes) : (index += 1) {
        const ch = parsed.data[index];
        if (ch == 0) return .ok;
        const status = output_format.append_bytes(output, output_len_bytes, &[_]u8{ch});
        if (status != .ok) return status;
    }
    return .runtime_error;
}

pub fn input_exhausted_for_token(state: *const ExecState) bool {
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    while (index < input_text.len and std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    return index >= input_text.len;
}

pub fn input_exhausted_at_eof(state: *const ExecState) bool {
    return state.input_offset_bytes >= state.input_text.len;
}

pub fn read_next_input_int(state: *ExecState) ?i32 {
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    while (index < input_text.len and std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    if (index >= input_text.len) return null;

    var sign: i64 = 1;
    if (input_text[index] == '-') {
        sign = -1;
        index += 1;
    } else if (input_text[index] == '+') {
        index += 1;
    }

    if (index >= input_text.len) return null;
    if (!std.ascii.isDigit(input_text[index])) return null;

    var value: i64 = 0;
    while (index < input_text.len and std.ascii.isDigit(input_text[index])) : (index += 1) {
        value = value * 10 + (input_text[index] - '0');
    }
    value *= sign;

    if (value < std.math.minInt(i32)) return null;
    if (value > std.math.maxInt(i32)) return null;
    state.input_offset_bytes = @intCast(index);
    return @intCast(value);
}

pub fn read_next_input_float(state: *ExecState) ?f32 {
    const token = read_next_input_token(state) orelse return null;
    return std.fmt.parseFloat(f32, token) catch null;
}

pub fn read_next_input_double(state: *ExecState) ?f64 {
    const token = read_next_input_token(state) orelse return null;
    return std.fmt.parseFloat(f64, token) catch null;
}

pub fn read_next_input_char(state: *ExecState) ?i32 {
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    if (index >= input_text.len) return null;
    const byte = input_text[index];
    index += 1;
    state.input_offset_bytes = @intCast(index);
    return byte;
}

pub fn read_next_input_token(state: *ExecState) ?[]const u8 {
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    while (index < input_text.len and std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    if (index >= input_text.len) return null;

    const start = index;
    while (index < input_text.len and !std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    state.input_offset_bytes = @intCast(index);
    return input_text[start..index];
}

pub fn syscall_read_string(
    parsed: *Program,
    state: *ExecState,
    buffer_address: u32,
    length: i32,
) bool {
    var max_length = length - 1;
    var add_null_byte = true;
    if (max_length < 0) {
        max_length = 0;
        add_null_byte = false;
    }

    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    const start = index;
    while (index < input_text.len and input_text[index] != '\n') : (index += 1) {}
    const line_end = index;
    if (index < input_text.len and input_text[index] == '\n') {
        index += 1;
    }
    state.input_offset_bytes = @intCast(index);

    const line = input_text[start..line_end];
    const line_len_i32: i32 = @intCast(line.len);
    var string_length = @min(max_length, line_len_i32);
    if (string_length < 0) string_length = 0;

    var i: i32 = 0;
    while (i < string_length) : (i += 1) {
        const src_index: usize = @intCast(i);
        const dst_address = buffer_address + @as(u32, @intCast(i));
        if (!write_u8(parsed, state, dst_address, line[src_index])) return false;
    }

    if (string_length < max_length) {
        const newline_address = buffer_address + @as(u32, @intCast(string_length));
        if (!write_u8(parsed, state, newline_address, '\n')) return false;
        string_length += 1;
    }

    if (add_null_byte) {
        const null_address = buffer_address + @as(u32, @intCast(string_length));
        if (!write_u8(parsed, state, null_address, 0)) return false;
    }

    return true;
}

pub fn syscall_sbrk(state: *ExecState, allocation_size: i32) ?u32 {
    if (allocation_size < 0) return null;
    const old_len = state.heap_len_bytes;
    var new_len = old_len + @as(u32, @intCast(allocation_size));
    if ((new_len & 3) != 0) {
        new_len += 4 - (new_len & 3);
    }
    if (new_len > heap_capacity_bytes) return null;
    state.heap_len_bytes = new_len;
    return heap_base_addr + old_len;
}

pub fn read_c_string_from_data(
    parsed: *Program,
    state: *ExecState,
    address: u32,
    buffer: *[virtual_file_name_capacity_bytes]u8,
) ?[]const u8 {
    var index: u32 = 0;
    while (index < buffer.len) : (index += 1) {
        const ch = read_u8(parsed, state, address + index) orelse return null;
        if (ch == 0) {
            return buffer[0..index];
        }
        buffer[index] = ch;
    }
    return null;
}

pub const OpenFileMode = enum {
    truncate,
    append,
};

pub fn find_virtual_file_by_name(state: *ExecState, name: []const u8) ?u32 {
    var i: u32 = 0;
    while (i < max_virtual_file_count) : (i += 1) {
        const file = &state.virtual_files[i];
        if (!file.in_use) continue;
        const existing_name = file.name[0..file.name_len_bytes];
        if (std.mem.eql(u8, existing_name, name)) {
            return i;
        }
    }
    return null;
}

pub fn open_or_create_virtual_file(state: *ExecState, name: []const u8, mode: OpenFileMode) ?u32 {
    if (find_virtual_file_by_name(state, name)) |existing_index| {
        if (mode == .truncate) {
            state.virtual_files[existing_index].len_bytes = 0;
        }
        return existing_index;
    }

    var i: u32 = 0;
    while (i < max_virtual_file_count) : (i += 1) {
        const file = &state.virtual_files[i];
        if (file.in_use) continue;
        if (name.len > virtual_file_name_capacity_bytes) return null;
        @memset(file.name[0..], 0);
        std.mem.copyForwards(u8, file.name[0..name.len], name);
        file.name_len_bytes = @intCast(name.len);
        file.len_bytes = 0;
        file.in_use = true;
        @memset(file.data[0..], 0);
        return i;
    }

    return null;
}

pub fn allocate_open_file(state: *ExecState, file_index: u32, flags: i32, position_bytes: u32) i32 {
    var i: u32 = 0;
    while (i < max_open_file_count) : (i += 1) {
        const open_file = &state.open_files[i];
        if (open_file.in_use) continue;
        open_file.in_use = true;
        open_file.file_index = file_index;
        open_file.flags = flags;
        open_file.position_bytes = position_bytes;
        return @intCast(i + 3);
    }
    return -1;
}

pub fn get_open_file(state: *ExecState, fd: i32) ?*OpenFile {
    if (fd < 3) return null;
    const index_u32: u32 = @intCast(fd - 3);
    if (index_u32 >= max_open_file_count) return null;
    const open_file = &state.open_files[index_u32];
    if (!open_file.in_use) return null;
    return open_file;
}

pub fn sanitize_midi_parameter(value: i32, default_value: i32) i32 {
    if (value < 0 or value > 127) return default_value;
    return value;
}

pub fn sanitize_midi_duration(value: i32, default_value: i32) i32 {
    if (value < 0) return default_value;
    return value;
}

pub fn current_time_millis_bits() u64 {
    const builtin = @import("builtin");
    if (builtin.target.cpu.arch == .wasm32) {
        return 1;
    }
    const millis_i64 = std.time.milliTimestamp();
    return @bitCast(millis_i64);
}

pub fn syscall_headless_dialog_termination(
    state: *ExecState,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    const status = output_format.append_bytes(
        output,
        output_len_bytes,
        "\nProgram terminated when maximum step limit -1 reached.\n\n",
    );
    if (status != .ok) return status;
    state.halted = true;
    return .ok;
}

// =========================================================================
// File I/O syscall helpers
// =========================================================================

pub fn syscall_open_file(parsed: *Program, state: *ExecState) i32 {
    const filename_address: u32 = @bitCast(read_reg(state, 4));
    const flags = read_reg(state, 5);

    var filename_buffer: [virtual_file_name_capacity_bytes]u8 = undefined;
    const filename = read_c_string_from_data(parsed, state, filename_address, &filename_buffer) orelse return -1;

    const file_index = switch (flags) {
        0 => find_virtual_file_by_name(state, filename) orelse return -1,
        1 => open_or_create_virtual_file(state, filename, .truncate) orelse return -1,
        9 => open_or_create_virtual_file(state, filename, .append) orelse return -1,
        else => return -1,
    };

    const position_bytes: u32 = if (flags == 9) state.virtual_files[file_index].len_bytes else 0;
    return allocate_open_file(state, file_index, flags, position_bytes);
}

pub fn syscall_read_file(parsed: *Program, state: *ExecState) ?i32 {
    const fd = read_reg(state, 4);
    const target_address: u32 = @bitCast(read_reg(state, 5));
    const requested_count = read_reg(state, 6);
    if (requested_count < 0) return -1;

    const open_file = get_open_file(state, fd) orelse return -1;
    const file = &state.virtual_files[open_file.file_index];
    if (!file.in_use) return -1;

    if (open_file.position_bytes > file.len_bytes) return -1;
    const available = file.len_bytes - open_file.position_bytes;
    const request_u32: u32 = @intCast(requested_count);
    const copy_count = @min(request_u32, available);

    var i: u32 = 0;
    while (i < copy_count) : (i += 1) {
        const source_index: usize = @intCast(open_file.position_bytes + i);
        if (!write_u8(parsed, state, target_address + i, file.data[source_index])) return null;
    }

    open_file.position_bytes += copy_count;
    return @intCast(copy_count);
}

pub fn syscall_write_file(parsed: *Program, state: *ExecState) ?i32 {
    const fd = read_reg(state, 4);
    const source_address: u32 = @bitCast(read_reg(state, 5));
    const requested_count = read_reg(state, 6);
    if (requested_count < 0) return -1;

    const open_file = get_open_file(state, fd) orelse return -1;
    const file = &state.virtual_files[open_file.file_index];
    if (!file.in_use) return -1;

    if (open_file.position_bytes > virtual_file_data_capacity_bytes) return -1;
    const write_capacity = virtual_file_data_capacity_bytes - open_file.position_bytes;
    const request_u32: u32 = @intCast(requested_count);
    const write_count = @min(request_u32, write_capacity);

    var i: u32 = 0;
    while (i < write_count) : (i += 1) {
        const byte = read_u8(parsed, state, source_address + i) orelse return null;
        const target_index: usize = @intCast(open_file.position_bytes + i);
        file.data[target_index] = byte;
    }

    open_file.position_bytes += write_count;
    if (open_file.position_bytes > file.len_bytes) {
        file.len_bytes = open_file.position_bytes;
    }

    return @intCast(write_count);
}

pub fn syscall_close_file(state: *ExecState) bool {
    const fd = read_reg(state, 4);
    const open_file = get_open_file(state, fd) orelse return false;
    open_file.in_use = false;
    open_file.file_index = 0;
    open_file.position_bytes = 0;
    open_file.flags = 0;
    return true;
}
