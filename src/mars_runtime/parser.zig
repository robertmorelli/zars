const std = @import("std");
const types = @import("types.zig");
const label_resolver = @import("label_resolver.zig");

const operand_parse = @import("operand_parse.zig");
const engine_data = @import("engine_data.zig");

const Program = types.Program;
const StatusCode = types.StatusCode;
const LineInstruction = types.LineInstruction;
const max_instruction_count = types.max_instruction_count;
const max_label_count = types.max_label_count;
const max_token_len = types.max_token_len;
const data_capacity_bytes = types.data_capacity_bytes;
const max_text_word_count = types.max_text_word_count;

// Forward declaration for pseudo-op expansion.
const pseudo_expander = @import("pseudo_expander.zig");

pub const directives = struct {
    pub const text = ".text";
    pub const ktext = ".ktext";
    pub const data = ".data";
    pub const kdata = ".kdata";
    pub const globl = ".globl";
    pub const extern_dir = ".extern";
    pub const set_dir = ".set";
    pub const align_dir = ".align";
    pub const asciiz = ".asciiz";
    pub const ascii = ".ascii";
    pub const space = ".space";
    pub const byte = ".byte";
    pub const half = ".half";
    pub const word = ".word";
    pub const float_dir = ".float";
    pub const double_dir = ".double";
};

pub fn parse_program(program_text: []const u8, parsed: *Program) StatusCode {
    parsed.instruction_count = 0;
    parsed.text_word_count = 0;
    parsed.label_count = 0;
    parsed.data_len_bytes = 0;
    parsed.data_label_count = 0;
    parsed.fixup_count = 0;
    @memset(parsed.data[0..], 0);
    @memset(parsed.instruction_word_indices[0..], 0);
    @memset(parsed.text_word_to_instruction_index[0..], 0);
    @memset(parsed.text_word_to_instruction_valid[0..], false);

    var in_text_section = true;

    var line_iterator = std.mem.splitScalar(u8, program_text, '\n');
    while (line_iterator.next()) |raw_line| {
        var line_buffer: [512]u8 = undefined;
        const line = normalize_line(raw_line, &line_buffer) orelse continue;

        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, directives.text) or std.mem.startsWith(u8, line, directives.ktext)) {
            in_text_section = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, directives.data) or std.mem.startsWith(u8, line, directives.kdata)) {
            in_text_section = false;
            continue;
        }
        if (std.mem.startsWith(u8, line, directives.globl)) continue;
        if (std.mem.startsWith(u8, line, directives.extern_dir)) continue;
        if (std.mem.startsWith(u8, line, directives.set_dir)) continue;

        var active_line = line;
        const colon_index_optional = std.mem.indexOfScalar(u8, active_line, ':');
        if (colon_index_optional) |colon_index| {
            const label_slice = operand_parse.trim_ascii(active_line[0..colon_index]);
            if (label_slice.len == 0) return .parse_error;
            active_line = operand_parse.trim_ascii(active_line[colon_index + 1 ..]);
            if (in_text_section) {
                if (!register_label(parsed, label_slice)) return .parse_error;
            } else {
                align_for_data_directive(parsed, active_line) catch return .parse_error;
                if (!register_data_label(parsed, label_slice)) return .parse_error;
            }
            if (active_line.len == 0) continue;
        }

        if (in_text_section) {
            if (active_line[0] == '.') continue;
            if (!register_instruction(parsed, active_line)) return .parse_error;
        } else {
            if (active_line[0] != '.') continue;
            if (!register_data_directive(parsed, active_line)) return .parse_error;
        }
    }

    if (!compute_text_layout(parsed)) return .parse_error;
    if (!label_resolver.resolve_fixups(parsed)) return .parse_error;
    return .ok;
}

fn normalize_line(raw_line: []const u8, line_buffer: *[512]u8) ?[]const u8 {
    const comment_index = std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len;
    const no_comment = raw_line[0..comment_index];
    const trimmed = operand_parse.trim_ascii(no_comment);
    if (trimmed.len == 0) return null;
    if (trimmed.len > line_buffer.len) return null;

    @memset(line_buffer[0..], 0);
    std.mem.copyForwards(u8, line_buffer[0..trimmed.len], trimmed);
    return line_buffer[0..trimmed.len];
}

fn register_label(parsed: *Program, label_slice: []const u8) bool {
    if (parsed.label_count >= max_label_count) return false;
    if (label_slice.len > max_token_len) return false;

    var i: u32 = 0;
    while (i < parsed.label_count) : (i += 1) {
        const existing = &parsed.labels[i];
        if (std.mem.eql(u8, existing.name[0..existing.len], label_slice)) {
            return false;
        }
    }

    const label = &parsed.labels[parsed.label_count];
    @memset(label.name[0..], 0);
    std.mem.copyForwards(u8, label.name[0..label_slice.len], label_slice);
    label.len = @intCast(label_slice.len);
    label.instruction_index = parsed.instruction_count;
    parsed.label_count += 1;
    return true;
}

fn register_data_label(parsed: *Program, label_slice: []const u8) bool {
    if (parsed.data_label_count >= max_label_count) return false;
    if (label_slice.len > max_token_len) return false;

    var i: u32 = 0;
    while (i < parsed.data_label_count) : (i += 1) {
        const existing = &parsed.data_labels[i];
        if (std.mem.eql(u8, existing.name[0..existing.len], label_slice)) return false;
    }

    const label = &parsed.data_labels[parsed.data_label_count];
    @memset(label.name[0..], 0);
    std.mem.copyForwards(u8, label.name[0..label_slice.len], label_slice);
    label.len = @intCast(label_slice.len);
    label.instruction_index = parsed.data_len_bytes;
    parsed.data_label_count += 1;
    return true;
}

fn align_for_data_directive(parsed: *Program, directive_line: []const u8) !void {
    if (std.mem.startsWith(u8, directive_line, directives.align_dir)) {
        const rest = operand_parse.trim_ascii(directive_line[directives.align_dir.len..]);
        const pow = operand_parse.parse_immediate(rest) orelse return error.OutOfBounds;
        if (pow < 0 or pow > 16) return error.OutOfBounds;
        const alignment: u32 = @as(u32, 1) << @as(u5, @intCast(pow));
        try engine_data.align_data(parsed, alignment);
        return;
    }
    if (std.mem.startsWith(u8, directive_line, directives.half)) {
        try engine_data.align_data(parsed, 2);
        return;
    }
    if (std.mem.startsWith(u8, directive_line, directives.word)) {
        try engine_data.align_data(parsed, 4);
        return;
    }
    if (std.mem.startsWith(u8, directive_line, directives.float_dir)) {
        try engine_data.align_data(parsed, 4);
        return;
    }
    if (std.mem.startsWith(u8, directive_line, directives.double_dir)) {
        try engine_data.align_data(parsed, 8);
        return;
    }
}

fn register_data_directive(parsed: *Program, directive_line: []const u8) bool {
    if (std.mem.startsWith(u8, directive_line, directives.align_dir)) {
        const rest = operand_parse.trim_ascii(directive_line[directives.align_dir.len..]);
        const pow = operand_parse.parse_immediate(rest) orelse return false;
        if (pow < 0 or pow > 16) return false;
        const alignment: u32 = @as(u32, 1) << @as(u5, @intCast(pow));
        engine_data.align_data(parsed, alignment) catch return false;
        return true;
    }

    if (std.mem.startsWith(u8, directive_line, directives.asciiz)) {
        const rest = operand_parse.trim_ascii(directive_line[directives.asciiz.len..]);
        if (rest.len < 2) return false;
        if (rest[0] != '"' or rest[rest.len - 1] != '"') return false;

        const quoted = rest[1 .. rest.len - 1];
        var i: usize = 0;
        while (i < quoted.len) : (i += 1) {
            if (parsed.data_len_bytes >= data_capacity_bytes) return false;
            const ch = quoted[i];
            if (ch == '\\' and i + 1 < quoted.len) {
                const next = quoted[i + 1];
                if (next == 'n') {
                    parsed.data[parsed.data_len_bytes] = '\n';
                    parsed.data_len_bytes += 1;
                    i += 1;
                    continue;
                }
            }
            parsed.data[parsed.data_len_bytes] = ch;
            parsed.data_len_bytes += 1;
        }

        if (parsed.data_len_bytes >= data_capacity_bytes) return false;
        parsed.data[parsed.data_len_bytes] = 0;
        parsed.data_len_bytes += 1;
        return true;
    }

    if (std.mem.startsWith(u8, directive_line, directives.ascii)) {
        const rest = operand_parse.trim_ascii(directive_line[directives.ascii.len..]);
        if (rest.len < 2) return false;
        if (rest[0] != '"' or rest[rest.len - 1] != '"') return false;

        const quoted = rest[1 .. rest.len - 1];
        var i: usize = 0;
        while (i < quoted.len) : (i += 1) {
            if (parsed.data_len_bytes >= data_capacity_bytes) return false;
            const ch = quoted[i];
            if (ch == '\\' and i + 1 < quoted.len) {
                const next = quoted[i + 1];
                if (next == 'n') {
                    parsed.data[parsed.data_len_bytes] = '\n';
                    parsed.data_len_bytes += 1;
                    i += 1;
                    continue;
                }
            }
            parsed.data[parsed.data_len_bytes] = ch;
            parsed.data_len_bytes += 1;
        }
        return true;
    }

    if (std.mem.startsWith(u8, directive_line, directives.space)) {
        const rest = operand_parse.trim_ascii(directive_line[directives.space.len..]);
        const byte_count = operand_parse.parse_immediate(rest) orelse return false;
        if (byte_count < 0) return false;
        var i: u32 = 0;
        while (i < @as(u32, @intCast(byte_count))) : (i += 1) {
            if (parsed.data_len_bytes >= data_capacity_bytes) return false;
            parsed.data[parsed.data_len_bytes] = 0;
            parsed.data_len_bytes += 1;
        }
        return true;
    }

    if (std.mem.startsWith(u8, directive_line, directives.byte)) {
        const rest = operand_parse.trim_ascii(directive_line[directives.byte.len..]);
        return engine_data.parse_numeric_data_list(parsed, rest, 1);
    }

    if (std.mem.startsWith(u8, directive_line, directives.half)) {
        engine_data.align_data(parsed, 2) catch return false;
        const rest = operand_parse.trim_ascii(directive_line[directives.half.len..]);
        return engine_data.parse_numeric_data_list(parsed, rest, 2);
    }

    if (std.mem.startsWith(u8, directive_line, directives.word)) {
        engine_data.align_data(parsed, 4) catch return false;
        const rest = operand_parse.trim_ascii(directive_line[directives.word.len..]);
        return engine_data.parse_numeric_data_list(parsed, rest, 4);
    }

    if (std.mem.startsWith(u8, directive_line, directives.float_dir)) {
        engine_data.align_data(parsed, 4) catch return false;
        const rest = operand_parse.trim_ascii(directive_line[directives.float_dir.len..]);
        return engine_data.parse_float_data_list(parsed, rest);
    }

    if (std.mem.startsWith(u8, directive_line, directives.double_dir)) {
        engine_data.align_data(parsed, 8) catch return false;
        const rest = operand_parse.trim_ascii(directive_line[directives.double_dir.len..]);
        return engine_data.parse_double_data_list(parsed, rest);
    }

    if (std.mem.startsWith(u8, directive_line, directives.globl)) return true;
    if (std.mem.startsWith(u8, directive_line, directives.extern_dir)) return true;
    if (std.mem.startsWith(u8, directive_line, directives.set_dir)) return true;

    return false;
}

fn register_instruction(parsed: *Program, line: []const u8) bool {
    if (parsed.instruction_count >= max_instruction_count) return false;

    var instruction = LineInstruction{
        .op = [_]u8{0} ** max_token_len,
        .op_len = 0,
        .operands = [_][max_token_len]u8{[_]u8{0} ** max_token_len} ** 3,
        .operand_lens = [_]u8{0} ** 3,
        .operand_count = 0,
    };

    var op_and_rest = std.mem.tokenizeAny(u8, line, " \t");
    const op_token = op_and_rest.next() orelse return false;
    if (op_token.len > max_token_len) return false;

    std.mem.copyForwards(u8, instruction.op[0..op_token.len], op_token);
    instruction.op_len = @intCast(op_token.len);

    const op_end_index = std.mem.indexOf(u8, line, op_token) orelse return false;
    const rest_start = op_end_index + op_token.len;
    if (rest_start >= line.len) {
        if (pseudo_expander.try_expand_pseudo_op(parsed, &instruction)) return true;
        parsed.instructions[parsed.instruction_count] = instruction;
        parsed.instruction_count += 1;
        return true;
    }

    const rest = operand_parse.trim_ascii(line[rest_start..]);
    if (rest.len == 0) {
        if (pseudo_expander.try_expand_pseudo_op(parsed, &instruction)) return true;
        parsed.instructions[parsed.instruction_count] = instruction;
        parsed.instruction_count += 1;
        return true;
    }

    var operand_iterator = std.mem.splitScalar(u8, rest, ',');
    while (operand_iterator.next()) |operand_raw| {
        const operand = operand_parse.trim_ascii(operand_raw);
        if (operand.len == 0) continue;
        if (instruction.operand_count >= 3) return false;
        if (operand.len > max_token_len) return false;

        const operand_index: usize = instruction.operand_count;
        std.mem.copyForwards(
            u8,
            instruction.operands[operand_index][0..operand.len],
            operand,
        );
        instruction.operand_lens[operand_index] = @intCast(operand.len);
        instruction.operand_count += 1;
    }

    if (pseudo_expander.try_expand_pseudo_op(parsed, &instruction)) return true;
    parsed.instructions[parsed.instruction_count] = instruction;
    parsed.instruction_count += 1;
    return true;
}

fn compute_text_layout(parsed: *Program) bool {
    var word_index: u32 = 0;
    var instruction_index: u32 = 0;
    while (instruction_index < parsed.instruction_count) : (instruction_index += 1) {
        if (word_index >= max_text_word_count) return false;

        parsed.instruction_word_indices[instruction_index] = word_index;

        const instruction = parsed.instructions[instruction_index];
        const word_count = estimate_instruction_word_count(&instruction);
        if (word_count == 0) return false;
        if (word_index + word_count > max_text_word_count) return false;

        var offset: u32 = 0;
        while (offset < word_count) : (offset += 1) {
            parsed.text_word_to_instruction_index[word_index + offset] = instruction_index;
            parsed.text_word_to_instruction_valid[word_index + offset] = true;
        }

        word_index += word_count;
    }
    parsed.text_word_count = word_index;
    return true;
}

fn estimate_instruction_word_count(instruction: *const LineInstruction) u32 {
    return pseudo_expander.process_pseudo_op(null, instruction, false) orelse 1;
}
