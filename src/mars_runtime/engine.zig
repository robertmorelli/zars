const std = @import("std");
const assert = std.debug.assert;

pub const max_instruction_count: u32 = 4096;
pub const max_label_count: u32 = 1024;
pub const max_token_len: u32 = 64;
pub const data_capacity_bytes: u32 = 64 * 1024;
pub const max_text_word_count: u32 = max_instruction_count * 4;
pub const text_base_addr: u32 = 0x00400000;
pub const data_base_addr: u32 = 0x10010000;

const max_open_file_count: u32 = 16;
const max_virtual_file_count: u32 = 16;
const virtual_file_name_capacity_bytes: u32 = 256;
const virtual_file_data_capacity_bytes: u32 = 64 * 1024;
const max_random_stream_count: u32 = 16;

pub const StatusCode = enum(u32) {
    ok = 0,
    parse_error = 1,
    unsupported_instruction = 2,
    runtime_error = 3,
};

const Label = struct {
    name: [max_token_len]u8,
    len: u8,
    instruction_index: u32,
};

const LineInstruction = struct {
    op: [max_token_len]u8,
    op_len: u8,
    operands: [3][max_token_len]u8,
    operand_lens: [3]u8,
    operand_count: u8,
};

const Program = struct {
    instructions: [max_instruction_count]LineInstruction,
    instruction_count: u32,
    instruction_word_indices: [max_instruction_count]u32,
    text_word_count: u32,
    text_word_to_instruction_index: [max_text_word_count]u32,
    text_word_to_instruction_valid: [max_text_word_count]bool,
    labels: [max_label_count]Label,
    label_count: u32,
    data: [data_capacity_bytes]u8,
    data_len_bytes: u32,
    data_labels: [max_label_count]Label,
    data_label_count: u32,
};

const VirtualFile = struct {
    name: [virtual_file_name_capacity_bytes]u8,
    name_len_bytes: u32,
    data: [virtual_file_data_capacity_bytes]u8,
    len_bytes: u32,
    in_use: bool,
};

const OpenFile = struct {
    file_index: u32,
    position_bytes: u32,
    flags: i32,
    in_use: bool,
};

const JavaRandomState = struct {
    initialized: bool,
    stream_id: i32,
    seed: u64,
};

const ExecState = struct {
    regs: [32]i32,
    fp_regs: [32]u64,
    fp_condition_true: bool,
    hi: i32,
    lo: i32,
    pc: u32,
    halted: bool,
    delayed_branching_enabled: bool,
    smc_enabled: bool,
    pending_branch_valid: bool,
    pending_branch_target: u32,
    pending_branch_countdown: u8,
    input_text: []const u8,
    input_offset_bytes: u32,
    text_patch_words: [max_instruction_count]u32,
    text_patch_valid: [max_instruction_count]bool,
    open_files: [max_open_file_count]OpenFile,
    virtual_files: [max_virtual_file_count]VirtualFile,
    random_streams: [max_random_stream_count]JavaRandomState,
};

pub const RunResult = struct {
    status: StatusCode,
    output_len_bytes: u32,
};

pub const EngineOptions = struct {
    delayed_branching_enabled: bool,
    smc_enabled: bool,
    input_text: []const u8,
};

var parsed_program_storage: Program = undefined;
var exec_state_storage: ExecState = undefined;

pub fn run_program(program_text: []const u8, output: []u8, options: EngineOptions) RunResult {
    const parse_status = parse_program(program_text, &parsed_program_storage);
    if (parse_status != .ok) {
        return .{ .status = parse_status, .output_len_bytes = 0 };
    }

    var out_len_bytes: u32 = 0;
    const run_status = execute_program(&parsed_program_storage, output, &out_len_bytes, options);
    return .{ .status = run_status, .output_len_bytes = out_len_bytes };
}

fn parse_program(program_text: []const u8, parsed: *Program) StatusCode {
    parsed.instruction_count = 0;
    parsed.text_word_count = 0;
    parsed.label_count = 0;
    parsed.data_len_bytes = 0;
    parsed.data_label_count = 0;
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
        if (std.mem.eql(u8, line, ".text")) {
            in_text_section = true;
            continue;
        }
        if (std.mem.eql(u8, line, ".data")) {
            in_text_section = false;
            continue;
        }

        var active_line = line;
        const colon_index_optional = std.mem.indexOfScalar(u8, active_line, ':');
        if (colon_index_optional) |colon_index| {
            const label_slice = trim_ascii(active_line[0..colon_index]);
            if (label_slice.len == 0) return .parse_error;
            active_line = trim_ascii(active_line[colon_index + 1 ..]);
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
    return .ok;
}

fn align_for_data_directive(parsed: *Program, directive_line: []const u8) !void {
    if (std.mem.startsWith(u8, directive_line, ".half")) {
        try align_data(parsed, 2);
        return;
    }
    if (std.mem.startsWith(u8, directive_line, ".word")) {
        try align_data(parsed, 4);
        return;
    }
    if (std.mem.startsWith(u8, directive_line, ".float")) {
        try align_data(parsed, 4);
        return;
    }
    if (std.mem.startsWith(u8, directive_line, ".double")) {
        try align_data(parsed, 8);
        return;
    }
}

fn normalize_line(raw_line: []const u8, line_buffer: *[512]u8) ?[]const u8 {
    const comment_index = std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len;
    const no_comment = raw_line[0..comment_index];
    const trimmed = trim_ascii(no_comment);
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

fn register_data_directive(parsed: *Program, directive_line: []const u8) bool {
    if (std.mem.startsWith(u8, directive_line, ".asciiz")) {
        const rest = trim_ascii(directive_line[".asciiz".len..]);
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

    if (std.mem.startsWith(u8, directive_line, ".space")) {
        const rest = trim_ascii(directive_line[".space".len..]);
        const byte_count = parse_immediate(rest) orelse return false;
        if (byte_count < 0) return false;
        var i: u32 = 0;
        while (i < @as(u32, @intCast(byte_count))) : (i += 1) {
            if (parsed.data_len_bytes >= data_capacity_bytes) return false;
            parsed.data[parsed.data_len_bytes] = 0;
            parsed.data_len_bytes += 1;
        }
        return true;
    }

    if (std.mem.startsWith(u8, directive_line, ".byte")) {
        const rest = trim_ascii(directive_line[".byte".len..]);
        return parse_numeric_data_list(parsed, rest, 1);
    }

    if (std.mem.startsWith(u8, directive_line, ".half")) {
        align_data(parsed, 2) catch return false;
        const rest = trim_ascii(directive_line[".half".len..]);
        return parse_numeric_data_list(parsed, rest, 2);
    }

    if (std.mem.startsWith(u8, directive_line, ".word")) {
        align_data(parsed, 4) catch return false;
        const rest = trim_ascii(directive_line[".word".len..]);
        return parse_numeric_data_list(parsed, rest, 4);
    }

    if (std.mem.startsWith(u8, directive_line, ".float")) {
        align_data(parsed, 4) catch return false;
        const rest = trim_ascii(directive_line[".float".len..]);
        return parse_float_data_list(parsed, rest);
    }

    if (std.mem.startsWith(u8, directive_line, ".double")) {
        align_data(parsed, 8) catch return false;
        const rest = trim_ascii(directive_line[".double".len..]);
        return parse_double_data_list(parsed, rest);
    }

    return false;
}

fn align_data(parsed: *Program, alignment: u32) !void {
    const remainder = parsed.data_len_bytes % alignment;
    if (remainder == 0) return;
    const padding = alignment - remainder;
    if (parsed.data_len_bytes + padding > data_capacity_bytes) return error.OutOfBounds;
    var i: u32 = 0;
    while (i < padding) : (i += 1) {
        parsed.data[parsed.data_len_bytes] = 0;
        parsed.data_len_bytes += 1;
    }
}

fn parse_numeric_data_list(parsed: *Program, rest: []const u8, byte_width: u32) bool {
    var item_iterator = std.mem.splitScalar(u8, rest, ',');
    while (item_iterator.next()) |item_raw| {
        const item = trim_ascii(item_raw);
        if (item.len == 0) continue;
        const value = parse_immediate(item) orelse return false;
        if (!append_numeric_value(parsed, value, byte_width)) return false;
    }
    return true;
}

fn append_numeric_value(parsed: *Program, value: i32, byte_width: u32) bool {
    if (parsed.data_len_bytes + byte_width > data_capacity_bytes) return false;
    const bits: u32 = @bitCast(value);
    if (byte_width == 1) {
        parsed.data[parsed.data_len_bytes] = @intCast(bits & 0xFF);
        parsed.data_len_bytes += 1;
        return true;
    }
    if (byte_width == 2) {
        parsed.data[parsed.data_len_bytes + 0] = @intCast((bits >> 8) & 0xFF);
        parsed.data[parsed.data_len_bytes + 1] = @intCast(bits & 0xFF);
        parsed.data_len_bytes += 2;
        return true;
    }
    if (byte_width == 4) {
        parsed.data[parsed.data_len_bytes + 0] = @intCast((bits >> 24) & 0xFF);
        parsed.data[parsed.data_len_bytes + 1] = @intCast((bits >> 16) & 0xFF);
        parsed.data[parsed.data_len_bytes + 2] = @intCast((bits >> 8) & 0xFF);
        parsed.data[parsed.data_len_bytes + 3] = @intCast(bits & 0xFF);
        parsed.data_len_bytes += 4;
        return true;
    }
    return false;
}

fn parse_float_data_list(parsed: *Program, rest: []const u8) bool {
    var item_iterator = std.mem.splitScalar(u8, rest, ',');
    while (item_iterator.next()) |item_raw| {
        const item = trim_ascii(item_raw);
        if (item.len == 0) continue;
        const value = std.fmt.parseFloat(f32, item) catch return false;
        if (!append_u32_be(parsed, @bitCast(value))) return false;
    }
    return true;
}

fn parse_double_data_list(parsed: *Program, rest: []const u8) bool {
    var item_iterator = std.mem.splitScalar(u8, rest, ',');
    while (item_iterator.next()) |item_raw| {
        const item = trim_ascii(item_raw);
        if (item.len == 0) continue;
        const value = std.fmt.parseFloat(f64, item) catch return false;
        if (!append_u64_be(parsed, @bitCast(value))) return false;
    }
    return true;
}

fn append_u32_be(parsed: *Program, value: u32) bool {
    if (parsed.data_len_bytes + 4 > data_capacity_bytes) return false;
    parsed.data[parsed.data_len_bytes + 0] = @intCast((value >> 24) & 0xFF);
    parsed.data[parsed.data_len_bytes + 1] = @intCast((value >> 16) & 0xFF);
    parsed.data[parsed.data_len_bytes + 2] = @intCast((value >> 8) & 0xFF);
    parsed.data[parsed.data_len_bytes + 3] = @intCast(value & 0xFF);
    parsed.data_len_bytes += 4;
    return true;
}

fn append_u64_be(parsed: *Program, value: u64) bool {
    if (parsed.data_len_bytes + 8 > data_capacity_bytes) return false;
    parsed.data[parsed.data_len_bytes + 0] = @intCast((value >> 56) & 0xFF);
    parsed.data[parsed.data_len_bytes + 1] = @intCast((value >> 48) & 0xFF);
    parsed.data[parsed.data_len_bytes + 2] = @intCast((value >> 40) & 0xFF);
    parsed.data[parsed.data_len_bytes + 3] = @intCast((value >> 32) & 0xFF);
    parsed.data[parsed.data_len_bytes + 4] = @intCast((value >> 24) & 0xFF);
    parsed.data[parsed.data_len_bytes + 5] = @intCast((value >> 16) & 0xFF);
    parsed.data[parsed.data_len_bytes + 6] = @intCast((value >> 8) & 0xFF);
    parsed.data[parsed.data_len_bytes + 7] = @intCast(value & 0xFF);
    parsed.data_len_bytes += 8;
    return true;
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
        parsed.instructions[parsed.instruction_count] = instruction;
        parsed.instruction_count += 1;
        return true;
    }

    const rest = trim_ascii(line[rest_start..]);
    if (rest.len == 0) {
        parsed.instructions[parsed.instruction_count] = instruction;
        parsed.instruction_count += 1;
        return true;
    }

    var operand_iterator = std.mem.splitScalar(u8, rest, ',');
    while (operand_iterator.next()) |operand_raw| {
        const operand = trim_ascii(operand_raw);
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
        parsed.text_word_to_instruction_index[word_index] = instruction_index;
        parsed.text_word_to_instruction_valid[word_index] = true;

        const instruction = parsed.instructions[instruction_index];
        const word_count = estimate_instruction_word_count(&instruction);
        if (word_count == 0) return false;
        if (word_index + word_count > max_text_word_count) return false;
        word_index += word_count;
    }
    parsed.text_word_count = word_index;
    return true;
}

fn estimate_instruction_word_count(instruction: *const LineInstruction) u32 {
    const op = instruction.op[0..instruction.op_len];

    if (std.mem.eql(u8, op, "li")) {
        if (instruction.operand_count != 2) return 1;
        const imm = parse_immediate(instruction_operand(instruction, 1)) orelse return 1;
        if (imm >= std.math.minInt(i16) and imm <= std.math.maxInt(i16)) return 1;
        if (imm >= 0 and imm <= std.math.maxInt(u16)) return 1;
        return 2;
    }

    if (std.mem.eql(u8, op, "la")) {
        return 2;
    }

    if (std.mem.eql(u8, op, "blt")) {
        return 2;
    }

    if (std.mem.eql(u8, op, "lb") or
        std.mem.eql(u8, op, "lbu") or
        std.mem.eql(u8, op, "lh") or
        std.mem.eql(u8, op, "lhu") or
        std.mem.eql(u8, op, "lw") or
        std.mem.eql(u8, op, "sb") or
        std.mem.eql(u8, op, "sh") or
        std.mem.eql(u8, op, "sw") or
        std.mem.eql(u8, op, "l.s") or
        std.mem.eql(u8, op, "l.d"))
    {
        if (instruction.operand_count < 2) return 1;
        const operand = instruction_operand(instruction, 1);
        if (std.mem.indexOfScalar(u8, operand, '(') == null) {
            return 2;
        }
        return 1;
    }

    if (std.mem.eql(u8, op, "add") or std.mem.eql(u8, op, "addu") or std.mem.eql(u8, op, "sub") or std.mem.eql(u8, op, "subu")) {
        if (instruction.operand_count != 3) return 1;
        if (parse_register(instruction_operand(instruction, 2)) != null) return 1;
        if (parse_immediate(instruction_operand(instruction, 2)) != null) return 2;
    }

    return 1;
}

fn execute_program(
    parsed: *Program,
    output: []u8,
    output_len_bytes: *u32,
    options: EngineOptions,
) StatusCode {
    const state = &exec_state_storage;
    state.* = .{
        .regs = [_]i32{0} ** 32,
        .fp_regs = [_]u64{0} ** 32,
        .fp_condition_true = false,
        .hi = 0,
        .lo = 0,
        .pc = 0,
        .halted = false,
        .delayed_branching_enabled = options.delayed_branching_enabled,
        .smc_enabled = options.smc_enabled,
        .pending_branch_valid = false,
        .pending_branch_target = 0,
        .pending_branch_countdown = 0,
        .input_text = options.input_text,
        .input_offset_bytes = 0,
        .text_patch_words = [_]u32{0} ** max_instruction_count,
        .text_patch_valid = [_]bool{false} ** max_instruction_count,
        .open_files = [_]OpenFile{.{
            .file_index = 0,
            .position_bytes = 0,
            .flags = 0,
            .in_use = false,
        }} ** max_open_file_count,
        .virtual_files = [_]VirtualFile{.{
            .name = [_]u8{0} ** virtual_file_name_capacity_bytes,
            .name_len_bytes = 0,
            .data = [_]u8{0} ** virtual_file_data_capacity_bytes,
            .len_bytes = 0,
            .in_use = false,
        }} ** max_virtual_file_count,
        .random_streams = [_]JavaRandomState{.{
            .initialized = false,
            .stream_id = 0,
            .seed = 0,
        }} ** max_random_stream_count,
    };

    output_len_bytes.* = 0;

    var step_count: u32 = 0;
    while (!state.halted) {
        if (state.pc >= parsed.instruction_count) {
            return .runtime_error;
        }
        if (step_count >= 200_000) {
            return .runtime_error;
        }
        step_count += 1;

        const current_pc = state.pc;
        state.pc += 1;

        var status: StatusCode = .ok;
        if (state.text_patch_valid[current_pc]) {
            const patched_word = state.text_patch_words[current_pc];
            status = execute_patched_instruction(
                parsed,
                state,
                patched_word,
                output,
                output_len_bytes,
            );
        } else {
            const instruction = parsed.instructions[current_pc];
            status = execute_instruction(parsed, state, &instruction, output, output_len_bytes);
        }
        if (status != .ok) return status;

        if (state.pending_branch_valid) {
            if (state.pending_branch_countdown == 0) {
                return .runtime_error;
            }
            state.pending_branch_countdown -= 1;
            if (state.pending_branch_countdown == 0) {
                state.pc = state.pending_branch_target;
                state.pending_branch_valid = false;
            }
        }
    }

    return .ok;
}

fn execute_instruction(
    parsed: *Program,
    state: *ExecState,
    instruction: *const LineInstruction,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    const op = instruction.op[0..instruction.op_len];

    if (std.mem.eql(u8, op, "li")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = parse_immediate(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_reg(state, rd, imm);
        return .ok;
    }

    if (std.mem.eql(u8, op, "move")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_reg(state, rd, read_reg(state, rs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "la")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = resolve_label_address(parsed, instruction_operand(instruction, 1)) orelse return .parse_error;
        write_reg(state, rd, @bitCast(address));
        return .ok;
    }

    if (std.mem.eql(u8, op, "l.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value = read_u32_be(parsed, address) orelse return .runtime_error;
        write_fp_single(state, fd, value);
        return .ok;
    }

    if (std.mem.eql(u8, op, "l.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((address & 7) != 0) return .runtime_error;
        const value = read_u64_be(parsed, address) orelse return .runtime_error;
        write_fp_double(state, fd, value);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lb")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value_u8 = read_u8(parsed, addr) orelse return .runtime_error;
        const value_i8: i8 = @bitCast(value_u8);
        write_reg(state, rt, value_i8);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lbu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value_u8 = read_u8(parsed, addr) orelse return .runtime_error;
        write_reg(state, rt, value_u8);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lh")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 1) != 0) return .runtime_error;
        const value_u16 = read_u16_be(parsed, addr) orelse return .runtime_error;
        const value_i16: i16 = @bitCast(value_u16);
        write_reg(state, rt, value_i16);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lhu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 1) != 0) return .runtime_error;
        const value_u16 = read_u16_be(parsed, addr) orelse return .runtime_error;
        write_reg(state, rt, value_u16);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lw")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const value = read_u32_be(parsed, addr) orelse return .runtime_error;
        write_reg(state, rt, @bitCast(value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sb")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u8(parsed, addr, @intCast(value & 0xFF))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sh")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 1) != 0) return .runtime_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u16_be(parsed, addr, @intCast(value & 0xFFFF))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sw")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u32(parsed, state, addr, value)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "add") or std.mem.eql(u8, op, "addu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs = if (parse_register(instruction_operand(instruction, 2))) |rt|
            read_reg(state, rt)
        else
            parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        write_reg(state, rd, read_reg(state, rs) +% rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "sub") or std.mem.eql(u8, op, "subu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs = if (parse_register(instruction_operand(instruction, 2))) |rt|
            read_reg(state, rt)
        else
            parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        write_reg(state, rd, read_reg(state, rs) -% rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "addiu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        write_reg(state, rt, read_reg(state, rs) +% imm);
        return .ok;
    }

    if (std.mem.eql(u8, op, "and")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(lhs & rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "or")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(lhs | rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "xor")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(lhs ^ rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "nor")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(~(lhs | rhs)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sll")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const shamt_i32 = parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
        const shamt: u5 = @intCast(shamt_i32);
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(rhs << shamt));
        return .ok;
    }

    if (std.mem.eql(u8, op, "srl")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const shamt_i32 = parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
        const shamt: u5 = @intCast(shamt_i32);
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(rhs >> shamt));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sra")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const shamt_i32 = parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
        const shamt: u5 = @intCast(shamt_i32);
        write_reg(state, rd, read_reg(state, rt) >> shamt);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mult")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: i64 = read_reg(state, rs);
        const rhs: i64 = read_reg(state, rt);
        const product: i64 = lhs * rhs;
        state.lo = @intCast(product & 0xFFFF_FFFF);
        state.hi = @intCast((product >> 32) & 0xFFFF_FFFF);
        return .ok;
    }

    if (std.mem.eql(u8, op, "div")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const divisor = read_reg(state, rt);
        if (divisor == 0) return .runtime_error;
        const dividend = read_reg(state, rs);
        state.lo = @divTrunc(dividend, divisor);
        state.hi = @rem(dividend, divisor);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mflo")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mfhi")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        write_reg(state, rd, state.hi);
        return .ok;
    }

    if (std.mem.eql(u8, op, "slt")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        write_reg(state, rd, if (read_reg(state, rs) < read_reg(state, rt)) 1 else 0);
        return .ok;
    }

    if (std.mem.eql(u8, op, "sltu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, if (lhs < rhs) 1 else 0);
        return .ok;
    }

    if (std.mem.eql(u8, op, "add.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f32 = @bitCast(read_fp_single(state, fs));
        const rhs: f32 = @bitCast(read_fp_single(state, ft));
        write_fp_single(state, fd, @bitCast(lhs + rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mul.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f32 = @bitCast(read_fp_single(state, fs));
        const rhs: f32 = @bitCast(read_fp_single(state, ft));
        write_fp_single(state, fd, @bitCast(lhs * rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sub.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f64 = @bitCast(read_fp_double(state, fs));
        const rhs: f64 = @bitCast(read_fp_double(state, ft));
        write_fp_double(state, fd, @bitCast(lhs - rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mov.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_fp_single(state, fd, read_fp_single(state, fs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mov.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_fp_double(state, fd, read_fp_double(state, fs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.eq.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fs = parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const ft = parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: f32 = @bitCast(read_fp_single(state, fs));
        const rhs: f32 = @bitCast(read_fp_single(state, ft));
        state.fp_condition_true = lhs == rhs;
        return .ok;
    }

    if (std.mem.eql(u8, op, "j")) {
        if (instruction.operand_count != 1) return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 0)) orelse return .parse_error;
        state.pc = target;
        return .ok;
    }

    if (std.mem.eql(u8, op, "bc1t")) {
        if (instruction.operand_count != 1) return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 0)) orelse return .parse_error;
        if (state.fp_condition_true) {
            state.pc = target;
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "blt")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rs) < read_reg(state, rt)) {
            state.pc = target;
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "beq")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rs) == read_reg(state, rt)) {
            if (state.delayed_branching_enabled) {
                state.pending_branch_valid = true;
                state.pending_branch_target = target;
                state.pending_branch_countdown = 2;
            } else {
                state.pc = target;
            }
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "jal")) {
        if (instruction.operand_count != 1) return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 0)) orelse return .parse_error;
        write_reg(state, 31, @intCast(state.pc));
        state.pc = target;
        return .ok;
    }

    if (std.mem.eql(u8, op, "jr")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const target_pc = read_reg(state, rs);
        if (target_pc < 0) return .runtime_error;
        state.pc = @intCast(target_pc);
        return .ok;
    }

    if (std.mem.eql(u8, op, "neg")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_reg(state, rd, -%read_reg(state, rs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "not")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(read_reg(state, rs));
        write_reg(state, rd, @bitCast(~value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "syscall")) {
        return execute_syscall(parsed, state, output, output_len_bytes);
    }

    if (std.mem.eql(u8, op, "nop")) {
        return .ok;
    }

    return .unsupported_instruction;
}

fn execute_patched_instruction(
    parsed: *Program,
    state: *ExecState,
    word: u32,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    const opcode = word >> 26;
    if (opcode == 0) {
        if (word == 0) return .ok;
        const funct = word & 0x3F;
        if (funct == 0x0C) {
            return execute_syscall(parsed, state, output, output_len_bytes);
        }
        return .unsupported_instruction;
    }

    if (opcode == 2) {
        const target_index_field = word & 0x03FF_FFFF;
        const target_address = target_index_field << 2;
        const target_index = text_address_to_instruction_index(parsed, target_address) orelse return .runtime_error;
        state.pc = target_index;
        return .ok;
    }

    return .unsupported_instruction;
}

fn execute_syscall(
    parsed: *Program,
    state: *ExecState,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    const v0 = read_reg(state, 2);

    if (v0 == 1) {
        const value = read_reg(state, 4);
        return append_formatted(output, output_len_bytes, "{}", .{value});
    }

    if (v0 == 2) {
        const bits = read_fp_single(state, 12);
        const value: f32 = @bitCast(bits);
        return append_java_float(output, output_len_bytes, value);
    }

    if (v0 == 3) {
        const bits = read_fp_double(state, 12);
        const value: f64 = @bitCast(bits);
        return append_java_double(output, output_len_bytes, value);
    }

    if (v0 == 4) {
        const address: u32 = @bitCast(read_reg(state, 4));
        if (address < data_base_addr) return .runtime_error;
        const data_offset = address - data_base_addr;
        return append_c_string_from_data(parsed, data_offset, output, output_len_bytes);
    }

    if (v0 == 5) {
        const value = read_next_input_int(state) orelse return .runtime_error;
        write_reg(state, 2, value);
        return .ok;
    }

    if (v0 == 10) {
        const newline_status = append_bytes(output, output_len_bytes, "\n");
        if (newline_status != .ok) return newline_status;
        state.halted = true;
        return .ok;
    }

    if (v0 == 11) {
        const a0: u32 = @bitCast(read_reg(state, 4));
        const ch: u8 = @intCast(a0 & 0xFF);
        return append_bytes(output, output_len_bytes, &[_]u8{ch});
    }

    if (v0 == 13) {
        const fd = syscall_open_file(parsed, state);
        write_reg(state, 2, fd);
        return .ok;
    }

    if (v0 == 14) {
        const count = syscall_read_file(parsed, state) orelse return .runtime_error;
        write_reg(state, 2, count);
        return .ok;
    }

    if (v0 == 15) {
        const count = syscall_write_file(parsed, state) orelse return .runtime_error;
        write_reg(state, 2, count);
        return .ok;
    }

    if (v0 == 16) {
        const close_status = syscall_close_file(state);
        write_reg(state, 2, close_status);
        return .ok;
    }

    if (v0 == 34) {
        const value: u32 = @bitCast(read_reg(state, 4));
        return append_formatted(output, output_len_bytes, "0x{x:0>8}", .{value});
    }

    if (v0 == 35) {
        const value: u32 = @bitCast(read_reg(state, 4));
        var temp: [32]u8 = undefined;
        var index: usize = 0;
        while (index < temp.len) : (index += 1) {
            const bit_index: u5 = @intCast(31 - index);
            temp[index] = if (((value >> bit_index) & 1) == 1) '1' else '0';
        }
        return append_bytes(output, output_len_bytes, temp[0..]);
    }

    if (v0 == 36) {
        const value: u32 = @bitCast(read_reg(state, 4));
        return append_formatted(output, output_len_bytes, "{}", .{value});
    }

    if (v0 == 40) {
        const stream_id = read_reg(state, 4);
        const seed = read_reg(state, 5);
        set_random_seed(state, stream_id, seed) orelse return .runtime_error;
        return .ok;
    }

    if (v0 == 41) {
        const stream_id = read_reg(state, 4);
        const random_value = random_next_int(state, stream_id) orelse return .runtime_error;
        write_reg(state, 4, random_value);
        return .ok;
    }

    if (v0 == 42) {
        const stream_id = read_reg(state, 4);
        const bound = read_reg(state, 5);
        const random_value = random_next_int_bound(state, stream_id, bound) orelse return .runtime_error;
        write_reg(state, 4, random_value);
        return .ok;
    }

    if (v0 == 43) {
        const stream_id = read_reg(state, 4);
        const random_value = random_next_float(state, stream_id) orelse return .runtime_error;
        write_fp_single(state, 0, @bitCast(random_value));
        return .ok;
    }

    if (v0 == 44) {
        const stream_id = read_reg(state, 4);
        const random_value = random_next_double(state, stream_id) orelse return .runtime_error;
        write_fp_double(state, 0, @bitCast(random_value));
        return .ok;
    }

    if (v0 == 60) {
        // MARS extension: clear screen. Command-mode behavior is effectively no-op.
        return .ok;
    }

    return .unsupported_instruction;
}

fn append_formatted(output: []u8, output_len_bytes: *u32, comptime fmt: []const u8, args: anytype) StatusCode {
    var temp: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&temp, fmt, args) catch return .runtime_error;
    return append_bytes(output, output_len_bytes, text);
}

fn append_java_float(output: []u8, output_len_bytes: *u32, value: f32) StatusCode {
    var temp: [128]u8 = undefined;
    const raw = std.fmt.bufPrint(&temp, "{}", .{value}) catch return .runtime_error;
    return append_java_float_like_text(output, output_len_bytes, raw);
}

fn append_java_double(output: []u8, output_len_bytes: *u32, value: f64) StatusCode {
    var temp: [128]u8 = undefined;
    const raw = std.fmt.bufPrint(&temp, "{}", .{value}) catch return .runtime_error;
    return append_java_float_like_text(output, output_len_bytes, raw);
}

fn append_java_float_like_text(output: []u8, output_len_bytes: *u32, raw: []const u8) StatusCode {
    const has_decimal = std.mem.indexOfScalar(u8, raw, '.') != null;
    const has_exponent = std.mem.indexOfScalar(u8, raw, 'e') != null or
        std.mem.indexOfScalar(u8, raw, 'E') != null;
    if (has_decimal or has_exponent) {
        return append_bytes(output, output_len_bytes, raw);
    }
    if (std.mem.eql(u8, raw, "nan")) return append_bytes(output, output_len_bytes, raw);
    if (std.mem.eql(u8, raw, "inf")) return append_bytes(output, output_len_bytes, raw);
    if (std.mem.eql(u8, raw, "-inf")) return append_bytes(output, output_len_bytes, raw);
    return append_formatted(output, output_len_bytes, "{s}.0", .{raw});
}

fn append_bytes(output: []u8, output_len_bytes: *u32, text: []const u8) StatusCode {
    const start: u32 = output_len_bytes.*;
    const end: u32 = start + @as(u32, @intCast(text.len));
    if (end > output.len) return .runtime_error;

    const start_index: usize = @intCast(start);
    const end_index: usize = @intCast(end);
    std.mem.copyForwards(u8, output[start_index..end_index], text);
    output_len_bytes.* = end;
    return .ok;
}

fn find_label(parsed: *Program, label_name: []const u8) ?u32 {
    var i: u32 = 0;
    while (i < parsed.label_count) : (i += 1) {
        const label = parsed.labels[i];
        if (std.mem.eql(u8, label.name[0..label.len], label_name)) {
            return label.instruction_index;
        }
    }
    return null;
}

fn find_data_label(parsed: *Program, label_name: []const u8) ?u32 {
    var i: u32 = 0;
    while (i < parsed.data_label_count) : (i += 1) {
        const label = parsed.data_labels[i];
        if (std.mem.eql(u8, label.name[0..label.len], label_name)) {
            return label.instruction_index;
        }
    }
    return null;
}

fn resolve_label_address(parsed: *Program, label_name: []const u8) ?u32 {
    if (find_data_label(parsed, label_name)) |data_offset| {
        return data_base_addr + data_offset;
    }
    if (find_label(parsed, label_name)) |instruction_index| {
        const word_index = parsed.instruction_word_indices[instruction_index];
        return text_base_addr + word_index * 4;
    }
    return null;
}

fn resolve_load_address(parsed: *Program, state: *ExecState, operand_text: []const u8) ?u32 {
    if (std.mem.indexOfScalar(u8, operand_text, '(') != null) {
        return compute_memory_address(state, operand_text);
    }
    return resolve_label_address(parsed, operand_text);
}

fn text_address_to_instruction_index(parsed: *Program, address: u32) ?u32 {
    if (address < text_base_addr) return null;
    const relative = address - text_base_addr;
    if ((relative & 3) != 0) return null;
    const word_index = relative / 4;
    if (word_index >= parsed.text_word_count) return null;
    if (!parsed.text_word_to_instruction_valid[word_index]) return null;
    return parsed.text_word_to_instruction_index[word_index];
}

fn write_u32(parsed: *Program, state: *ExecState, address: u32, value: u32) bool {
    if (write_u32_be(parsed, address, value)) return true;
    return write_text_patch_word(parsed, state, address, value);
}

fn write_text_patch_word(parsed: *Program, state: *ExecState, address: u32, value: u32) bool {
    if (!state.smc_enabled) return false;
    const instruction_index = text_address_to_instruction_index(parsed, address) orelse return false;
    state.text_patch_words[instruction_index] = value;
    state.text_patch_valid[instruction_index] = true;
    return true;
}

fn append_c_string_from_data(
    parsed: *Program,
    data_offset: u32,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    if (data_offset >= parsed.data_len_bytes) return .runtime_error;
    var index: u32 = data_offset;
    while (index < parsed.data_len_bytes) : (index += 1) {
        const ch = parsed.data[index];
        if (ch == 0) return .ok;
        const status = append_bytes(output, output_len_bytes, &[_]u8{ch});
        if (status != .ok) return status;
    }
    return .runtime_error;
}
fn instruction_operand(instruction: *const LineInstruction, index: u8) []const u8 {
    assert(index < instruction.operand_count);
    return instruction.operands[index][0..instruction.operand_lens[index]];
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

fn write_reg(state: *ExecState, reg: u5, value: i32) void {
    if (reg == 0) return;
    state.regs[reg] = value;
}

fn parse_immediate(text: []const u8) ?i32 {
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

fn parse_register(text: []const u8) ?u5 {
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

    const numeric = std.fmt.parseInt(u8, name, 10) catch return null;
    if (numeric > 31) return null;
    return @intCast(numeric);
}

fn parse_fp_register(text: []const u8) ?u5 {
    if (text.len < 3) return null;
    if (text[0] != '$') return null;
    if (text[1] != 'f') return null;

    const numeric = std.fmt.parseInt(u8, text[2..], 10) catch return null;
    if (numeric > 31) return null;
    return @intCast(numeric);
}

fn read_fp_single(state: *ExecState, reg: u5) u32 {
    return @intCast(state.fp_regs[reg] & 0xFFFF_FFFF);
}

fn write_fp_single(state: *ExecState, reg: u5, bits: u32) void {
    state.fp_regs[reg] = bits;
}

fn read_fp_double(state: *ExecState, reg: u5) u64 {
    return state.fp_regs[reg];
}

fn write_fp_double(state: *ExecState, reg: u5, bits: u64) void {
    state.fp_regs[reg] = bits;
}

fn compute_memory_address(state: *ExecState, text: []const u8) ?u32 {
    const open_paren = std.mem.indexOfScalar(u8, text, '(') orelse return null;
    const close_paren = std.mem.indexOfScalar(u8, text, ')') orelse return null;
    if (close_paren <= open_paren + 1) return null;

    const offset_text = trim_ascii(text[0..open_paren]);
    const base_text = trim_ascii(text[open_paren + 1 .. close_paren]);
    const offset = if (offset_text.len == 0) 0 else parse_immediate(offset_text) orelse return null;
    const base_reg = parse_register(base_text) orelse return null;
    const base_addr: u32 = @bitCast(read_reg(state, base_reg));
    return base_addr +% @as(u32, @bitCast(offset));
}

fn data_address_to_offset(parsed: *Program, address: u32) ?u32 {
    if (address < data_base_addr) return null;
    const offset = address - data_base_addr;
    if (offset >= parsed.data_len_bytes) return null;
    return offset;
}

fn read_u8(parsed: *Program, address: u32) ?u8 {
    const offset = data_address_to_offset(parsed, address) orelse return null;
    return parsed.data[offset];
}

fn read_u16_be(parsed: *Program, address: u32) ?u16 {
    const b0 = read_u8(parsed, address) orelse return null;
    const b1 = read_u8(parsed, address + 1) orelse return null;
    return (@as(u16, b0) << 8) | @as(u16, b1);
}

fn read_u32_be(parsed: *Program, address: u32) ?u32 {
    const b0 = read_u8(parsed, address) orelse return null;
    const b1 = read_u8(parsed, address + 1) orelse return null;
    const b2 = read_u8(parsed, address + 2) orelse return null;
    const b3 = read_u8(parsed, address + 3) orelse return null;
    return (@as(u32, b0) << 24) | (@as(u32, b1) << 16) | (@as(u32, b2) << 8) | @as(u32, b3);
}

fn read_u64_be(parsed: *Program, address: u32) ?u64 {
    const b0 = read_u8(parsed, address + 0) orelse return null;
    const b1 = read_u8(parsed, address + 1) orelse return null;
    const b2 = read_u8(parsed, address + 2) orelse return null;
    const b3 = read_u8(parsed, address + 3) orelse return null;
    const b4 = read_u8(parsed, address + 4) orelse return null;
    const b5 = read_u8(parsed, address + 5) orelse return null;
    const b6 = read_u8(parsed, address + 6) orelse return null;
    const b7 = read_u8(parsed, address + 7) orelse return null;
    return (@as(u64, b0) << 56) |
        (@as(u64, b1) << 48) |
        (@as(u64, b2) << 40) |
        (@as(u64, b3) << 32) |
        (@as(u64, b4) << 24) |
        (@as(u64, b5) << 16) |
        (@as(u64, b6) << 8) |
        @as(u64, b7);
}

fn write_u8(parsed: *Program, address: u32, value: u8) bool {
    const offset = data_address_to_offset(parsed, address) orelse return false;
    parsed.data[offset] = value;
    return true;
}

fn write_u16_be(parsed: *Program, address: u32, value: u16) bool {
    return write_u8(parsed, address, @intCast((value >> 8) & 0xFF)) and
        write_u8(parsed, address + 1, @intCast(value & 0xFF));
}

fn write_u32_be(parsed: *Program, address: u32, value: u32) bool {
    return write_u8(parsed, address, @intCast((value >> 24) & 0xFF)) and
        write_u8(parsed, address + 1, @intCast((value >> 16) & 0xFF)) and
        write_u8(parsed, address + 2, @intCast((value >> 8) & 0xFF)) and
        write_u8(parsed, address + 3, @intCast(value & 0xFF));
}

fn read_next_input_int(state: *ExecState) ?i32 {
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

fn syscall_open_file(parsed: *Program, state: *ExecState) i32 {
    const filename_address: u32 = @bitCast(read_reg(state, 4));
    const flags = read_reg(state, 5);

    var filename_buffer: [virtual_file_name_capacity_bytes]u8 = undefined;
    const filename = read_c_string_from_data(parsed, filename_address, &filename_buffer) orelse return -1;

    const file_index = switch (flags) {
        0 => find_virtual_file_by_name(state, filename) orelse return -1,
        1 => open_or_create_virtual_file(state, filename, .truncate) orelse return -1,
        9 => open_or_create_virtual_file(state, filename, .append) orelse return -1,
        else => return -1,
    };

    const position_bytes: u32 = if (flags == 9) state.virtual_files[file_index].len_bytes else 0;
    return allocate_open_file(state, file_index, flags, position_bytes);
}

fn syscall_read_file(parsed: *Program, state: *ExecState) ?i32 {
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
        if (!write_u8(parsed, target_address + i, file.data[source_index])) return null;
    }

    open_file.position_bytes += copy_count;
    return @intCast(copy_count);
}

fn syscall_write_file(parsed: *Program, state: *ExecState) ?i32 {
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
        const byte = read_u8(parsed, source_address + i) orelse return null;
        const target_index: usize = @intCast(open_file.position_bytes + i);
        file.data[target_index] = byte;
    }

    open_file.position_bytes += write_count;
    if (open_file.position_bytes > file.len_bytes) {
        file.len_bytes = open_file.position_bytes;
    }

    return @intCast(write_count);
}

fn syscall_close_file(state: *ExecState) i32 {
    const fd = read_reg(state, 4);
    const open_file = get_open_file(state, fd) orelse return -1;
    open_file.in_use = false;
    open_file.file_index = 0;
    open_file.position_bytes = 0;
    open_file.flags = 0;
    return 0;
}

const OpenFileMode = enum {
    truncate,
    append,
};

fn open_or_create_virtual_file(state: *ExecState, name: []const u8, mode: OpenFileMode) ?u32 {
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

fn find_virtual_file_by_name(state: *ExecState, name: []const u8) ?u32 {
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

fn allocate_open_file(state: *ExecState, file_index: u32, flags: i32, position_bytes: u32) i32 {
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

fn get_open_file(state: *ExecState, fd: i32) ?*OpenFile {
    if (fd < 3) return null;
    const index_u32: u32 = @intCast(fd - 3);
    if (index_u32 >= max_open_file_count) return null;
    const open_file = &state.open_files[index_u32];
    if (!open_file.in_use) return null;
    return open_file;
}

fn read_c_string_from_data(
    parsed: *Program,
    address: u32,
    buffer: *[virtual_file_name_capacity_bytes]u8,
) ?[]const u8 {
    var index: u32 = 0;
    while (index < buffer.len) : (index += 1) {
        const ch = read_u8(parsed, address + index) orelse return null;
        if (ch == 0) {
            return buffer[0..index];
        }
        buffer[index] = ch;
    }
    return null;
}

fn set_random_seed(state: *ExecState, stream_id: i32, seed: i32) ?void {
    const random_state = ensure_random_stream(state, stream_id) orelse return null;
    java_random_set_seed(random_state, seed);
}

fn random_next_int(state: *ExecState, stream_id: i32) ?i32 {
    const random_state = ensure_random_stream(state, stream_id) orelse return null;
    return @bitCast(java_random_next_bits(random_state, 32));
}

fn random_next_int_bound(state: *ExecState, stream_id: i32, bound: i32) ?i32 {
    if (bound <= 0) return null;
    const random_state = ensure_random_stream(state, stream_id) orelse return null;
    if ((bound & -bound) == bound) {
        const value = (@as(i64, bound) * @as(i64, @intCast(java_random_next_bits(random_state, 31)))) >> 31;
        return @intCast(value);
    }

    const bound_i64: i64 = bound;
    while (true) {
        const bits_i64: i64 = @intCast(java_random_next_bits(random_state, 31));
        const value_i64 = @mod(bits_i64, bound_i64);
        if (bits_i64 - value_i64 + (bound_i64 - 1) >= 0) {
            return @intCast(value_i64);
        }
    }
}

fn random_next_float(state: *ExecState, stream_id: i32) ?f32 {
    const random_state = ensure_random_stream(state, stream_id) orelse return null;
    const numerator = java_random_next_bits(random_state, 24);
    return @as(f32, @floatFromInt(numerator)) / 16777216.0;
}

fn random_next_double(state: *ExecState, stream_id: i32) ?f64 {
    const random_state = ensure_random_stream(state, stream_id) orelse return null;
    const high = @as(u64, java_random_next_bits(random_state, 26));
    const low = @as(u64, java_random_next_bits(random_state, 27));
    const numerator = (high << 27) + low;
    return @as(f64, @floatFromInt(numerator)) / 9007199254740992.0;
}

fn ensure_random_stream(state: *ExecState, stream_id: i32) ?*JavaRandomState {
    var i: u32 = 0;
    while (i < max_random_stream_count) : (i += 1) {
        const random_state = &state.random_streams[i];
        if (!random_state.initialized) continue;
        if (random_state.stream_id == stream_id) {
            return random_state;
        }
    }

    i = 0;
    while (i < max_random_stream_count) : (i += 1) {
        const random_state = &state.random_streams[i];
        if (random_state.initialized) continue;
        random_state.initialized = true;
        random_state.stream_id = stream_id;
        java_random_set_seed(random_state, stream_id);
        return random_state;
    }

    return null;
}

fn java_random_set_seed(random_state: *JavaRandomState, seed: i32) void {
    const multiplier: u64 = 0x5DEECE66D;
    const mask: u64 = (1 << 48) - 1;
    const seed_signed: i64 = seed;
    const seed_bits: u64 = @bitCast(seed_signed);
    random_state.seed = (seed_bits ^ multiplier) & mask;
}

fn java_random_next_bits(random_state: *JavaRandomState, bits: u8) u32 {
    assert(bits <= 32);
    const multiplier: u64 = 0x5DEECE66D;
    const addend: u64 = 0xB;
    const mask: u64 = (1 << 48) - 1;
    const bits_u6: u6 = @intCast(bits);
    random_state.seed = (random_state.seed *% multiplier +% addend) & mask;
    const shift: u6 = 48 - bits_u6;
    return @intCast(random_state.seed >> shift);
}

fn trim_ascii(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

test "engine executes integer arithmetic fixture" {
    const program =
        \\main:
        \\    li $t0, 40
        \\    li $t1, 2
        \\    add $t2, $t0, $t1
        \\    move $a0, $t2
        \\    li $v0, 1
        \\    syscall
        \\    jal print_newline
        \\    li $v0, 10
        \\    syscall
        \\print_newline:
        \\    li $v0, 11
        \\    li $a0, 10
        \\    syscall
        \\    jr $ra
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("42\n", out[0..result.output_len_bytes]);
}
