const std = @import("std");
const operand_parse = @import("operand_parse.zig");

pub const source_capacity_bytes: usize = 1024 * 1024;

const max_eqv_count: u32 = 256;
const max_macro_count: u32 = 256;
const max_macro_param_count: u32 = 16;
const max_line_count: u32 = 8192;
const max_macro_body_line_count: u32 = 8192;
const line_substitute_capacity_bytes: usize = 4096;

const EqvPair = struct {
    name: []const u8,
    value: []const u8,
};

const MacroEntry = struct {
    name: []const u8,
    param_count: u32,
    params: [max_macro_param_count][]const u8,
    body_start: u32,
    body_count: u32,
};

var eqv_buffer_a: [source_capacity_bytes]u8 = undefined;
var eqv_buffer_b: [source_capacity_bytes]u8 = undefined;
var macro_buffer: [source_capacity_bytes]u8 = undefined;
var substitute_buffer_a: [line_substitute_capacity_bytes]u8 = undefined;
var substitute_buffer_b: [line_substitute_capacity_bytes]u8 = undefined;

pub fn preprocess_source(source_text: []const u8) ?[]const u8 {
    const with_eqv = apply_eqv(source_text) orelse return null;
    const with_macros = expand_macros(with_eqv) orelse return null;
    return with_macros;
}

fn apply_eqv(source_text: []const u8) ?[]const u8 {
    var eqv_pairs: [max_eqv_count]EqvPair = undefined;
    var eqv_count: u32 = 0;
    collect_eqv_pairs(source_text, &eqv_pairs, &eqv_count);
    if (eqv_count == 0) return source_text;

    var current = source_text;
    var use_buffer_a = true;
    var index: u32 = 0;
    while (index < eqv_count) : (index += 1) {
        const pair = eqv_pairs[index];
        const target = if (use_buffer_a) eqv_buffer_a[0..] else eqv_buffer_b[0..];
        current = replace_eqv_tokens(current, pair.name, pair.value, target) orelse return null;
        use_buffer_a = !use_buffer_a;
    }
    return current;
}

fn collect_eqv_pairs(source_text: []const u8, pairs: *[max_eqv_count]EqvPair, count: *u32) void {
    count.* = 0;
    var line_iterator = std.mem.splitScalar(u8, source_text, '\n');
    while (line_iterator.next()) |line| {
        const trimmed = operand_parse.trim_ascii(line);
        if (!std.mem.startsWith(u8, trimmed, ".eqv")) continue;

        const rest = operand_parse.trim_ascii(trimmed[".eqv".len..]);
        if (rest.len == 0) continue;
        var name_end: usize = 0;
        while (name_end < rest.len and !ascii_space(rest[name_end])) : (name_end += 1) {}
        if (name_end == 0) continue;

        const name = rest[0..name_end];
        if (!token_name_valid(name)) continue;
        const value = operand_parse.trim_ascii(rest[name_end..]);
        if (value.len == 0) continue;

        const existing = find_eqv_pair(pairs, count.*, name);
        if (existing) |existing_index| {
            pairs[existing_index].value = value;
            continue;
        }
        if (count.* >= max_eqv_count) continue;
        pairs[count.*] = .{ .name = name, .value = value };
        count.* += 1;
    }
}

fn find_eqv_pair(pairs: *const [max_eqv_count]EqvPair, count: u32, name: []const u8) ?u32 {
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        if (std.mem.eql(u8, pairs[index].name, name)) {
            return index;
        }
    }
    return null;
}

fn replace_eqv_tokens(
    source_text: []const u8,
    token_name: []const u8,
    token_value: []const u8,
    target: []u8,
) ?[]const u8 {
    if (token_name.len == 0) return source_text;
    var source_index: usize = 0;
    var target_len_bytes: usize = 0;
    while (source_index < source_text.len) {
        if (token_boundary_match(source_text, source_index, token_name)) {
            if (target_len_bytes + token_value.len > target.len) return null;
            std.mem.copyForwards(
                u8,
                target[target_len_bytes .. target_len_bytes + token_value.len],
                token_value,
            );
            target_len_bytes += token_value.len;
            source_index += token_name.len;
            continue;
        }
        if (target_len_bytes >= target.len) return null;
        target[target_len_bytes] = source_text[source_index];
        target_len_bytes += 1;
        source_index += 1;
    }
    return target[0..target_len_bytes];
}

fn token_boundary_match(source_text: []const u8, index: usize, token_name: []const u8) bool {
    if (index + token_name.len > source_text.len) return false;
    if (!std.mem.eql(u8, source_text[index .. index + token_name.len], token_name)) return false;
    const left_boundary = if (index == 0) true else !word_character(source_text[index - 1]);
    const right_boundary = if (index + token_name.len >= source_text.len)
        true
    else
        !word_character(source_text[index + token_name.len]);
    return left_boundary and right_boundary;
}

fn expand_macros(source_text: []const u8) ?[]const u8 {
    var lines: [max_line_count][]const u8 = undefined;
    var line_count: u32 = 0;
    split_lines(source_text, &lines, &line_count) orelse return null;

    var macros: [max_macro_count]MacroEntry = undefined;
    var macro_count: u32 = 0;
    var macro_body_lines: [max_macro_body_line_count][]const u8 = undefined;
    var macro_body_count: u32 = 0;
    var body_lines: [max_line_count][]const u8 = undefined;
    var body_line_count: u32 = 0;

    var line_index: u32 = 0;
    while (line_index < line_count) {
        const line = lines[line_index];
        const trimmed = operand_parse.trim_ascii(line);
        if (!std.mem.startsWith(u8, trimmed, ".macro")) {
            if (body_line_count >= max_line_count) return null;
            body_lines[body_line_count] = line;
            body_line_count += 1;
            line_index += 1;
            continue;
        }

        var macro_name: []const u8 = undefined;
        var macro_params: [max_macro_param_count][]const u8 = undefined;
        var macro_param_count: u32 = 0;
        if (!parse_macro_header(trimmed, &macro_name, &macro_params, &macro_param_count)) {
            line_index += 1;
            continue;
        }
        if (macro_count >= max_macro_count) return null;
        var entry = MacroEntry{
            .name = macro_name,
            .param_count = macro_param_count,
            .params = [_][]const u8{""} ** max_macro_param_count,
            .body_start = macro_body_count,
            .body_count = 0,
        };
        var param_index: u32 = 0;
        while (param_index < macro_param_count) : (param_index += 1) {
            entry.params[param_index] = macro_params[param_index];
        }

        line_index += 1;
        while (line_index < line_count) : (line_index += 1) {
            const body_line = lines[line_index];
            if (std.mem.eql(u8, operand_parse.trim_ascii(body_line), ".end_macro")) {
                break;
            }
            if (macro_body_count >= max_macro_body_line_count) return null;
            macro_body_lines[macro_body_count] = body_line;
            macro_body_count += 1;
        }
        if (line_index < line_count and
            std.mem.eql(u8, operand_parse.trim_ascii(lines[line_index]), ".end_macro"))
        {
            line_index += 1;
        }
        entry.body_count = macro_body_count - entry.body_start;
        macros[macro_count] = entry;
        macro_count += 1;
    }

    var output_len_bytes: usize = 0;
    var first_line = true;
    var body_index: u32 = 0;
    while (body_index < body_line_count) : (body_index += 1) {
        const line = body_lines[body_index];
        const trimmed = operand_parse.trim_ascii(line);

        var call_name: []const u8 = undefined;
        var call_args: [max_macro_param_count][]const u8 = undefined;
        var call_arg_count: u32 = 0;
        if (!parse_macro_call(trimmed, &call_name, &call_args, &call_arg_count)) {
            append_joined_line(macro_buffer[0..], &output_len_bytes, line, &first_line) orelse return null;
            continue;
        }

        const macro_index = find_macro_entry(&macros, macro_count, call_name) orelse {
            append_joined_line(macro_buffer[0..], &output_len_bytes, line, &first_line) orelse return null;
            continue;
        };
        const macro = macros[macro_index];
        var macro_line_index: u32 = 0;
        while (macro_line_index < macro.body_count) : (macro_line_index += 1) {
            const macro_line = macro_body_lines[macro.body_start + macro_line_index];
            const expanded_line = substitute_macro_line(
                macro_line,
                macro.params[0..macro.param_count],
                call_args[0..call_arg_count],
            ) orelse return null;
            append_joined_line(
                macro_buffer[0..],
                &output_len_bytes,
                expanded_line,
                &first_line,
            ) orelse return null;
        }
    }
    return macro_buffer[0..output_len_bytes];
}

fn split_lines(source_text: []const u8, lines: *[max_line_count][]const u8, count: *u32) ?void {
    count.* = 0;
    var line_iterator = std.mem.splitScalar(u8, source_text, '\n');
    while (line_iterator.next()) |line| {
        if (count.* >= max_line_count) return null;
        lines[count.*] = line;
        count.* += 1;
    }
}

fn parse_macro_header(
    trimmed_header: []const u8,
    macro_name: *[]const u8,
    macro_params: *[max_macro_param_count][]const u8,
    macro_param_count: *u32,
) bool {
    macro_param_count.* = 0;
    if (!std.mem.startsWith(u8, trimmed_header, ".macro")) return false;
    var rest = trimmed_header[".macro".len..];
    if (rest.len == 0) return false;
    if (!ascii_space(rest[0])) return false;
    rest = operand_parse.trim_ascii(rest);
    if (rest.len == 0) return false;

    var name_end: usize = 0;
    while (name_end < rest.len and token_char(rest[name_end])) : (name_end += 1) {}
    if (name_end == 0) return false;

    const name = rest[0..name_end];
    if (!token_name_valid(name)) return false;
    rest = operand_parse.trim_ascii(rest[name_end..]);

    if (rest.len == 0) {
        macro_name.* = name;
        return true;
    }
    if (rest[0] != '(') return false;
    if (rest[rest.len - 1] != ')') return false;

    const params_text = rest[1 .. rest.len - 1];
    parse_comma_list(params_text, macro_params, macro_param_count) orelse return false;
    macro_name.* = name;
    return true;
}

fn parse_macro_call(
    trimmed_line: []const u8,
    call_name: *[]const u8,
    call_args: *[max_macro_param_count][]const u8,
    call_arg_count: *u32,
) bool {
    call_arg_count.* = 0;
    if (trimmed_line.len == 0) return false;
    if (!token_name_valid_prefix(trimmed_line)) return false;

    var name_end: usize = 0;
    while (name_end < trimmed_line.len and token_char(trimmed_line[name_end])) : (name_end += 1) {}
    const name = trimmed_line[0..name_end];
    if (!token_name_valid(name)) return false;

    var rest = operand_parse.trim_ascii(trimmed_line[name_end..]);
    if (rest.len == 0) {
        call_name.* = name;
        return true;
    }
    if (rest[0] != '(') return false;
    if (rest[rest.len - 1] != ')') return false;

    const args_text = rest[1 .. rest.len - 1];
    parse_comma_list(args_text, call_args, call_arg_count) orelse return false;
    call_name.* = name;
    return true;
}

fn parse_comma_list(
    raw_text: []const u8,
    output: *[max_macro_param_count][]const u8,
    output_count: *u32,
) ?void {
    output_count.* = 0;
    const trimmed = operand_parse.trim_ascii(raw_text);
    if (trimmed.len == 0) return;

    var list_iterator = std.mem.splitScalar(u8, trimmed, ',');
    while (list_iterator.next()) |part| {
        if (output_count.* >= max_macro_param_count) return null;
        output[output_count.*] = operand_parse.trim_ascii(part);
        output_count.* += 1;
    }
}

fn find_macro_entry(macros: *const [max_macro_count]MacroEntry, macro_count: u32, name: []const u8) ?u32 {
    var index: u32 = 0;
    while (index < macro_count) : (index += 1) {
        if (std.mem.eql(u8, macros[index].name, name)) return index;
    }
    return null;
}

fn substitute_macro_line(
    line: []const u8,
    params: []const []const u8,
    args: []const []const u8,
) ?[]const u8 {
    var current = line;
    var use_buffer_a = true;
    var index: usize = 0;
    while (index < params.len) : (index += 1) {
        const param = params[index];
        if (param.len == 0) continue;
        const arg = if (index < args.len) args[index] else "";
        const target = if (use_buffer_a) substitute_buffer_a[0..] else substitute_buffer_b[0..];
        current = replace_substring(current, param, arg, target) orelse return null;
        use_buffer_a = !use_buffer_a;
    }
    return current;
}

fn replace_substring(
    source_text: []const u8,
    pattern: []const u8,
    replacement: []const u8,
    target: []u8,
) ?[]const u8 {
    if (pattern.len == 0) return source_text;
    var source_index: usize = 0;
    var target_len_bytes: usize = 0;
    while (source_index < source_text.len) {
        if (source_index + pattern.len <= source_text.len and
            std.mem.eql(u8, source_text[source_index .. source_index + pattern.len], pattern))
        {
            if (target_len_bytes + replacement.len > target.len) return null;
            std.mem.copyForwards(
                u8,
                target[target_len_bytes .. target_len_bytes + replacement.len],
                replacement,
            );
            target_len_bytes += replacement.len;
            source_index += pattern.len;
            continue;
        }
        if (target_len_bytes >= target.len) return null;
        target[target_len_bytes] = source_text[source_index];
        target_len_bytes += 1;
        source_index += 1;
    }
    return target[0..target_len_bytes];
}

fn append_joined_line(
    output: []u8,
    output_len_bytes: *usize,
    line: []const u8,
    first_line: *bool,
) ?void {
    if (!first_line.*) {
        if (output_len_bytes.* >= output.len) return null;
        output[output_len_bytes.*] = '\n';
        output_len_bytes.* += 1;
    }
    if (output_len_bytes.* + line.len > output.len) return null;
    std.mem.copyForwards(
        u8,
        output[output_len_bytes.* .. output_len_bytes.* + line.len],
        line,
    );
    output_len_bytes.* += line.len;
    first_line.* = false;
}

fn ascii_space(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

fn token_name_valid_prefix(text: []const u8) bool {
    if (text.len == 0) return false;
    const first = text[0];
    return std.ascii.isAlphabetic(first) or first == '_';
}

fn token_name_valid(text: []const u8) bool {
    if (!token_name_valid_prefix(text)) return false;
    var index: usize = 1;
    while (index < text.len) : (index += 1) {
        if (!token_char(text[index])) return false;
    }
    return true;
}

fn token_char(ch: u8) bool {
    if (std.ascii.isAlphabetic(ch)) return true;
    if (std.ascii.isDigit(ch)) return true;
    return ch == '_';
}

fn word_character(ch: u8) bool {
    if (std.ascii.isAlphabetic(ch)) return true;
    if (std.ascii.isDigit(ch)) return true;
    return ch == '_';
}

test "source preprocess applies eqv with token boundaries" {
    const source =
        \\.eqv MAGIC 73
        \\li $t0, MAGIC
        \\li $t1, MAGIC_VALUE
    ;
    const preprocessed = preprocess_source(source) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, preprocessed, "li $t0, 73") != null);
    try std.testing.expect(std.mem.indexOf(u8, preprocessed, "li $t1, MAGIC_VALUE") != null);
}

test "source preprocess expands macro calls" {
    const source =
        \\.macro add_one(%reg)
        \\addi %reg, %reg, 1
        \\.end_macro
        \\add_one($t0)
    ;
    const preprocessed = preprocess_source(source) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("addi $t0, $t0, 1", preprocessed);
}

test "source preprocess applies eqv before macro expansion" {
    const source =
        \\.eqv VALUE 19
        \\.macro emit
        \\li $a0, VALUE
        \\.end_macro
        \\emit
    ;
    const preprocessed = preprocess_source(source) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("li $a0, 19", preprocessed);
}
