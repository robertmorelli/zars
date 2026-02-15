const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const fp_math = @import("fp_math.zig");
const output_format = @import("output_format.zig");
const java_random = @import("java_random.zig");
const operand_parse = @import("operand_parse.zig");
const source_preprocess = @import("source_preprocess.zig");
const model = @import("model.zig");

pub const max_instruction_count = model.max_instruction_count;
pub const max_label_count = model.max_label_count;
pub const max_token_len = model.max_token_len;
pub const data_capacity_bytes = model.data_capacity_bytes;
pub const max_text_word_count = model.max_text_word_count;
pub const text_base_addr = model.text_base_addr;
pub const data_base_addr = model.data_base_addr;
pub const heap_base_addr = model.heap_base_addr;
pub const heap_capacity_bytes = model.heap_capacity_bytes;

const max_open_file_count = model.max_open_file_count;
const max_virtual_file_count = model.max_virtual_file_count;
const virtual_file_name_capacity_bytes = model.virtual_file_name_capacity_bytes;
const virtual_file_data_capacity_bytes = model.virtual_file_data_capacity_bytes;
const max_random_stream_count = model.max_random_stream_count;

pub const StatusCode = model.StatusCode;
pub const RunResult = model.RunResult;
pub const EngineOptions = model.EngineOptions;

const Label = model.Label;
const LineInstruction = model.LineInstruction;
const Program = model.Program;
const VirtualFile = model.VirtualFile;
const OpenFile = model.OpenFile;
const JavaRandomState = model.JavaRandomState;
const DelayedBranchState = model.DelayedBranchState;
const ExecState = model.ExecState;

var parsed_program_storage: Program = undefined;
var exec_state_storage: ExecState = undefined;

// Step execution state - persists between step calls.
var step_output_buffer: []u8 = &[_]u8{};
var step_output_len_bytes: u32 = 0;
var step_count: u32 = 0;
var step_initialized: bool = false;

// MARS-compatible initial register values.
// $gp (28) = 0x10008000, $sp (29) = 0x7fffeffc
fn init_integer_registers() [32]i32 {
    var regs = [_]i32{0} ** 32;
    regs[28] = @bitCast(@as(u32, 0x10008000)); // $gp
    regs[29] = @bitCast(@as(u32, 0x7fffeffc)); // $sp
    return regs;
}

/// Emit a basic MIPS instruction during pseudo-op expansion.
/// Returns false if instruction array is full.
fn emit_instruction(parsed: *Program, op: []const u8, operands: []const []const u8) bool {
    if (parsed.instruction_count >= max_instruction_count) return false;

    var instruction = LineInstruction{
        .op = [_]u8{0} ** max_token_len,
        .op_len = 0,
        .operands = [_][max_token_len]u8{[_]u8{0} ** max_token_len} ** 3,
        .operand_lens = [_]u8{0} ** 3,
        .operand_count = 0,
    };

    if (op.len > max_token_len) return false;
    @memcpy(instruction.op[0..op.len], op);
    instruction.op_len = @intCast(op.len);

    if (operands.len > 3) return false;
    for (operands, 0..) |operand, i| {
        if (operand.len > max_token_len) return false;
        @memcpy(instruction.operands[i][0..operand.len], operand);
        instruction.operand_lens[i] = @intCast(operand.len);
    }
    instruction.operand_count = @intCast(operands.len);

    parsed.instructions[parsed.instruction_count] = instruction;
    parsed.instruction_count += 1;
    return true;
}

pub fn run_program(program_text: []const u8, output: []u8, options: EngineOptions) RunResult {
    // Parsing and execution share static storage to keep the runtime allocator-free.
    const preprocessed_text = source_preprocess.preprocess_source(program_text) orelse {
        return .{ .status = .parse_error, .output_len_bytes = 0 };
    };
    const parse_status = parse_program(preprocessed_text, &parsed_program_storage);
    if (parse_status != .ok) {
        return .{ .status = parse_status, .output_len_bytes = 0 };
    }

    var out_len_bytes: u32 = 0;
    const run_status = execute_program(&parsed_program_storage, output, &out_len_bytes, options);
    return .{ .status = run_status, .output_len_bytes = out_len_bytes };
}

pub fn snapshot_regs() *const [32]i32 {
    return &exec_state_storage.regs;
}

pub fn snapshot_fp_regs() *const [32]u32 {
    return &exec_state_storage.fp_regs;
}

pub fn snapshot_data_bytes() *const [data_capacity_bytes]u8 {
    return &parsed_program_storage.data;
}

pub fn snapshot_data_len_bytes() u32 {
    return parsed_program_storage.data_len_bytes;
}

pub fn snapshot_heap_bytes() *const [heap_capacity_bytes]u8 {
    return &exec_state_storage.heap;
}

pub fn snapshot_heap_len_bytes() u32 {
    return exec_state_storage.heap_len_bytes;
}

pub fn snapshot_hi() i32 {
    return exec_state_storage.hi;
}

pub fn snapshot_lo() i32 {
    return exec_state_storage.lo;
}

pub fn snapshot_pc() u32 {
    return exec_state_storage.pc;
}

pub fn snapshot_halted() bool {
    return exec_state_storage.halted;
}

pub fn snapshot_fp_condition_flags() u8 {
    return exec_state_storage.fp_condition_flags;
}

pub fn snapshot_instruction_count() u32 {
    return parsed_program_storage.instruction_count;
}

/// Initialize execution state for step-by-step execution.
/// Must be called before step_execution(). Returns parse_error if program is invalid.
pub fn init_execution(program_text: []const u8, output: []u8, options: EngineOptions) StatusCode {
    // Reset step state.
    step_output_buffer = output;
    step_output_len_bytes = 0;
    step_count = 0;
    step_initialized = false;

    // Parse program.
    const preprocessed_text = source_preprocess.preprocess_source(program_text) orelse {
        return .parse_error;
    };
    const parse_status = parse_program(preprocessed_text, &parsed_program_storage);
    if (parse_status != .ok) {
        return parse_status;
    }

    // Initialize execution state (same as execute_program).
    const state = &exec_state_storage;
    state.* = .{
        .regs = init_integer_registers(),
        .fp_regs = [_]u32{0} ** 32,
        .fp_condition_flags = 0,
        .cp0_regs = [_]i32{0} ** 32,
        .hi = 0,
        .lo = 0,
        .pc = 0,
        .halted = false,
        .delayed_branching_enabled = options.delayed_branching_enabled,
        .smc_enabled = options.smc_enabled,
        .delayed_branch_state = .cleared,
        .delayed_branch_target = 0,
        .input_text = options.input_text,
        .input_offset_bytes = 0,
        .text_patch_words = [_]u32{0} ** max_instruction_count,
        .text_patch_valid = [_]bool{false} ** max_instruction_count,
        .heap = [_]u8{0} ** heap_capacity_bytes,
        .heap_len_bytes = 0,
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

    step_initialized = true;
    return .ok;
}

/// Execute exactly one instruction. Returns status after the step.
/// - ok: instruction executed, program still running
/// - halted: program exited normally
/// - runtime_error: error occurred
pub fn step_execution() StatusCode {
    if (!step_initialized) {
        return .runtime_error;
    }

    const state = &exec_state_storage;
    const parsed = &parsed_program_storage;

    // Already halted - return halted status.
    if (state.halted) {
        return .halted;
    }

    // Check PC bounds.
    if (state.pc >= parsed.instruction_count) {
        return .runtime_error;
    }

    // Check step limit.
    if (step_count >= 200_000) {
        return .runtime_error;
    }
    step_count += 1;

    const current_pc = state.pc;
    state.pc += 1;

    var status: StatusCode = .ok;
    // If SMC patched this slot, execute the patched machine word.
    if (state.text_patch_valid[current_pc]) {
        const patched_word = state.text_patch_words[current_pc];
        status = execute_patched_instruction(
            parsed,
            state,
            current_pc,
            patched_word,
            step_output_buffer,
            &step_output_len_bytes,
        );
    } else {
        const instruction = parsed.instructions[current_pc];
        status = execute_instruction(parsed, state, &instruction, step_output_buffer, &step_output_len_bytes);
    }
    if (status == .needs_input) {
        // Rewind PC so the syscall instruction re-executes after input is supplied.
        state.pc = current_pc;
        step_count -= 1;
        return .needs_input;
    }
    if (status != .ok) return status;

    // Delayed branch sequencing.
    if (state.delayed_branch_state == .triggered) {
        state.pc = state.delayed_branch_target;
        state.delayed_branch_state = .cleared;
        state.delayed_branch_target = 0;
    } else if (state.delayed_branch_state == .registered) {
        state.delayed_branch_state = .triggered;
    }

    // Check if program halted after this instruction.
    if (state.halted) {
        return .halted;
    }

    return .ok;
}

/// Run at full speed until the program halts, errors, or needs input.
/// Returns: halted, runtime_error, or needs_input.
pub fn run_until_input() StatusCode {
    while (true) {
        const status = step_execution();
        switch (status) {
            .ok => continue,
            .needs_input, .halted, .runtime_error, .parse_error => return status,
        }
    }
}

/// Update the input slice to reflect newly appended bytes.
/// Called after the host writes additional bytes to input_storage.
pub fn update_input_slice(new_input: []const u8) void {
    exec_state_storage.input_text = new_input;
}

/// Get the current input consumption offset.
pub fn snapshot_input_offset_bytes() u32 {
    return exec_state_storage.input_offset_bytes;
}

/// Get the current output length (for step mode).
pub fn step_output_len() u32 {
    return step_output_len_bytes;
}

fn parse_program(program_text: []const u8, parsed: *Program) StatusCode {
    // Reset all parser-owned tables before each run.
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

    // Parser is line-oriented because MARS source format and directives are line-oriented.
    var line_iterator = std.mem.splitScalar(u8, program_text, '\n');
    while (line_iterator.next()) |raw_line| {
        var line_buffer: [512]u8 = undefined;
        const line = normalize_line(raw_line, &line_buffer) orelse continue;

        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, ".text") or std.mem.startsWith(u8, line, ".ktext")) {
            in_text_section = true;
            continue;
        }
        if (std.mem.startsWith(u8, line, ".data") or std.mem.startsWith(u8, line, ".kdata")) {
            in_text_section = false;
            continue;
        }
        if (std.mem.startsWith(u8, line, ".globl")) continue;
        if (std.mem.startsWith(u8, line, ".extern")) continue;
        if (std.mem.startsWith(u8, line, ".set")) continue;

        // Label handling is split from payload parsing so `label: instruction` and
        // `label: .directive` both map cleanly.
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

    // Build source-index <-> text-address mappings after parsing all instructions.
    if (!compute_text_layout(parsed)) return .parse_error;
    return .ok;
}

fn align_for_data_directive(parsed: *Program, directive_line: []const u8) !void {
    // Data labels should point at post-alignment addresses just like MARS.
    if (std.mem.startsWith(u8, directive_line, ".align")) {
        const rest = operand_parse.trim_ascii(directive_line[".align".len..]);
        const pow = operand_parse.parse_immediate(rest) orelse return error.OutOfBounds;
        if (pow < 0 or pow > 16) return error.OutOfBounds;
        const alignment: u32 = @as(u32, 1) << @as(u5, @intCast(pow));
        try align_data(parsed, alignment);
        return;
    }
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
    // Normalize by stripping comments and ASCII whitespace.
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
    // Reject duplicate labels to keep branch targets unambiguous.
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
    // Data labels map to byte offsets in the data segment.
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
    if (std.mem.startsWith(u8, directive_line, ".align")) {
        const rest = operand_parse.trim_ascii(directive_line[".align".len..]);
        const pow = operand_parse.parse_immediate(rest) orelse return false;
        if (pow < 0 or pow > 16) return false;
        const alignment: u32 = @as(u32, 1) << @as(u5, @intCast(pow));
        align_data(parsed, alignment) catch return false;
        return true;
    }

    if (std.mem.startsWith(u8, directive_line, ".asciiz")) {
        const rest = operand_parse.trim_ascii(directive_line[".asciiz".len..]);
        if (rest.len < 2) return false;
        if (rest[0] != '"' or rest[rest.len - 1] != '"') return false;

        // Keep escape handling minimal and explicit to match tested fixture usage.
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

    if (std.mem.startsWith(u8, directive_line, ".ascii")) {
        const rest = operand_parse.trim_ascii(directive_line[".ascii".len..]);
        if (rest.len < 2) return false;
        if (rest[0] != '"' or rest[rest.len - 1] != '"') return false;

        // `.ascii` mirrors `.asciiz` behavior without the trailing NUL byte.
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

    if (std.mem.startsWith(u8, directive_line, ".space")) {
        const rest = operand_parse.trim_ascii(directive_line[".space".len..]);
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

    if (std.mem.startsWith(u8, directive_line, ".byte")) {
        const rest = operand_parse.trim_ascii(directive_line[".byte".len..]);
        return parse_numeric_data_list(parsed, rest, 1);
    }

    if (std.mem.startsWith(u8, directive_line, ".half")) {
        align_data(parsed, 2) catch return false;
        const rest = operand_parse.trim_ascii(directive_line[".half".len..]);
        return parse_numeric_data_list(parsed, rest, 2);
    }

    if (std.mem.startsWith(u8, directive_line, ".word")) {
        align_data(parsed, 4) catch return false;
        const rest = operand_parse.trim_ascii(directive_line[".word".len..]);
        return parse_numeric_data_list(parsed, rest, 4);
    }

    if (std.mem.startsWith(u8, directive_line, ".float")) {
        align_data(parsed, 4) catch return false;
        const rest = operand_parse.trim_ascii(directive_line[".float".len..]);
        return parse_float_data_list(parsed, rest);
    }

    if (std.mem.startsWith(u8, directive_line, ".double")) {
        align_data(parsed, 8) catch return false;
        const rest = operand_parse.trim_ascii(directive_line[".double".len..]);
        return parse_double_data_list(parsed, rest);
    }

    if (std.mem.startsWith(u8, directive_line, ".globl")) {
        return true;
    }

    if (std.mem.startsWith(u8, directive_line, ".extern")) {
        return true;
    }

    if (std.mem.startsWith(u8, directive_line, ".set")) {
        return true;
    }

    return false;
}

fn align_data(parsed: *Program, alignment: u32) !void {
    // Zero-fill alignment gap so reads from padding are deterministic.
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
    // Numeric directive lists are comma-separated and tolerate spacing.
    var item_iterator = std.mem.splitScalar(u8, rest, ',');
    while (item_iterator.next()) |item_raw| {
        const item = operand_parse.trim_ascii(item_raw);
        if (item.len == 0) continue;
        const value = operand_parse.parse_immediate(item) orelse return false;
        if (!append_numeric_value(parsed, value, byte_width)) return false;
    }
    return true;
}

fn append_numeric_value(parsed: *Program, value: i32, byte_width: u32) bool {
    // MARS stores words in little-endian memory order.
    if (parsed.data_len_bytes + byte_width > data_capacity_bytes) return false;
    const bits: u32 = @bitCast(value);
    if (byte_width == 1) {
        parsed.data[parsed.data_len_bytes] = @intCast(bits & 0xFF);
        parsed.data_len_bytes += 1;
        return true;
    }
    if (byte_width == 2) {
        parsed.data[parsed.data_len_bytes + 0] = @intCast(bits & 0xFF);
        parsed.data[parsed.data_len_bytes + 1] = @intCast((bits >> 8) & 0xFF);
        parsed.data_len_bytes += 2;
        return true;
    }
    if (byte_width == 4) {
        parsed.data[parsed.data_len_bytes + 0] = @intCast(bits & 0xFF);
        parsed.data[parsed.data_len_bytes + 1] = @intCast((bits >> 8) & 0xFF);
        parsed.data[parsed.data_len_bytes + 2] = @intCast((bits >> 16) & 0xFF);
        parsed.data[parsed.data_len_bytes + 3] = @intCast((bits >> 24) & 0xFF);
        parsed.data_len_bytes += 4;
        return true;
    }
    return false;
}

fn parse_float_data_list(parsed: *Program, rest: []const u8) bool {
    // `.float` accepts comma-separated decimal literals.
    var item_iterator = std.mem.splitScalar(u8, rest, ',');
    while (item_iterator.next()) |item_raw| {
        const item = operand_parse.trim_ascii(item_raw);
        if (item.len == 0) continue;
        const value = std.fmt.parseFloat(f32, item) catch return false;
        if (!append_u32_be(parsed, @bitCast(value))) return false;
    }
    return true;
}

fn parse_double_data_list(parsed: *Program, rest: []const u8) bool {
    // `.double` accepts comma-separated decimal literals.
    var item_iterator = std.mem.splitScalar(u8, rest, ',');
    while (item_iterator.next()) |item_raw| {
        const item = operand_parse.trim_ascii(item_raw);
        if (item.len == 0) continue;
        const value = std.fmt.parseFloat(f64, item) catch return false;
        if (!append_u64_be(parsed, @bitCast(value))) return false;
    }
    return true;
}

fn append_u32_be(parsed: *Program, value: u32) bool {
    if (parsed.data_len_bytes + 4 > data_capacity_bytes) return false;
    parsed.data[parsed.data_len_bytes + 0] = @intCast(value & 0xFF);
    parsed.data[parsed.data_len_bytes + 1] = @intCast((value >> 8) & 0xFF);
    parsed.data[parsed.data_len_bytes + 2] = @intCast((value >> 16) & 0xFF);
    parsed.data[parsed.data_len_bytes + 3] = @intCast((value >> 24) & 0xFF);
    parsed.data_len_bytes += 4;
    return true;
}

fn append_u64_be(parsed: *Program, value: u64) bool {
    if (parsed.data_len_bytes + 8 > data_capacity_bytes) return false;
    parsed.data[parsed.data_len_bytes + 0] = @intCast(value & 0xFF);
    parsed.data[parsed.data_len_bytes + 1] = @intCast((value >> 8) & 0xFF);
    parsed.data[parsed.data_len_bytes + 2] = @intCast((value >> 16) & 0xFF);
    parsed.data[parsed.data_len_bytes + 3] = @intCast((value >> 24) & 0xFF);
    parsed.data[parsed.data_len_bytes + 4] = @intCast((value >> 32) & 0xFF);
    parsed.data[parsed.data_len_bytes + 5] = @intCast((value >> 40) & 0xFF);
    parsed.data[parsed.data_len_bytes + 6] = @intCast((value >> 48) & 0xFF);
    parsed.data[parsed.data_len_bytes + 7] = @intCast((value >> 56) & 0xFF);
    parsed.data_len_bytes += 8;
    return true;
}

/// Try to expand a pseudo-op into basic instructions.
/// Returns true if expanded (caller should NOT store the pseudo-op).
/// Returns false if not a pseudo-op (caller should store as-is).
fn try_expand_pseudo_op(parsed: *Program, instruction: *const LineInstruction) bool {
    const op = instruction.op[0..instruction.op_len];

    // li: Load Immediate
    if (std.mem.eql(u8, op, "li")) {
        if (instruction.operand_count != 2) return false;

        const rd_text = instruction_operand(instruction, 0);
        const imm_text = instruction_operand(instruction, 1);
        const imm = operand_parse.parse_immediate(imm_text) orelse return false;

        // Match MARS expansion order:
        // li $t1,-100   -> addiu RG1, $0, VL2   (sign-extended)
        // li $t1,100    -> ori RG1, $0, VL2U    (zero-extended unsigned)
        // li $t1,100000 -> lui $1, VHL2; ori RG1, $1, VL2U (32-bit)

        // If negative and fits in signed 16 bits, use addiu (sign-extend)
        if (imm >= std.math.minInt(i16) and imm < 0) {
            return emit_instruction(parsed, "addiu", &[_][]const u8{ rd_text, "$zero", imm_text });
        }

        // If non-negative and fits unsigned 16 bits, use ori
        if (imm >= 0 and imm <= std.math.maxInt(u16)) {
            return emit_instruction(parsed, "ori", &[_][]const u8{ rd_text, "$zero", imm_text });
        }

        // 32-bit immediate: expand to lui + ori
        // lui $at, HIGH(imm)
        // ori rd, $at, LOW(imm)
        const imm_u32 = @as(u32, @bitCast(imm));
        const high = @as(i32, @bitCast((imm_u32 >> 16) & 0xFFFF));
        const low = @as(i32, @bitCast(imm_u32 & 0xFFFF));

        // Format immediate values as strings for emit_instruction
        var high_str: [32]u8 = undefined;
        var low_str: [32]u8 = undefined;

        const high_len = std.fmt.bufPrint(&high_str, "{}", .{high}) catch return false;
        const low_len = std.fmt.bufPrint(&low_str, "{}", .{low}) catch return false;

        // Emit lui $at, high
        if (!emit_instruction(parsed, "lui", &[_][]const u8{ "$at", high_str[0..high_len.len] })) return false;

        // Emit ori rd, $at, low
        return emit_instruction(parsed, "ori", &[_][]const u8{ rd_text, "$at", low_str[0..low_len.len] });
    }

    // move: Move register
    if (std.mem.eql(u8, op, "move")) {
        if (instruction.operand_count != 2) return false;
        const rd_text = instruction_operand(instruction, 0);
        const rs_text = instruction_operand(instruction, 1);

        return emit_instruction(parsed, "addu", &[_][]const u8{ rd_text, rs_text, "$zero" });
    }

    return false; // Not a pseudo-op we're handling
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

    // Split mnemonic from operand tail first, then parse operands by comma.
    var op_and_rest = std.mem.tokenizeAny(u8, line, " \t");
    const op_token = op_and_rest.next() orelse return false;
    if (op_token.len > max_token_len) return false;

    std.mem.copyForwards(u8, instruction.op[0..op_token.len], op_token);
    instruction.op_len = @intCast(op_token.len);

    const op_end_index = std.mem.indexOf(u8, line, op_token) orelse return false;
    const rest_start = op_end_index + op_token.len;
    if (rest_start >= line.len) {
        // Try pseudo-op expansion first
        if (try_expand_pseudo_op(parsed, &instruction)) return true;
        parsed.instructions[parsed.instruction_count] = instruction;
        parsed.instruction_count += 1;
        return true;
    }

    const rest = operand_parse.trim_ascii(line[rest_start..]);
    if (rest.len == 0) {
        // Try pseudo-op expansion first
        if (try_expand_pseudo_op(parsed, &instruction)) return true;
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

    // Try pseudo-op expansion first
    if (try_expand_pseudo_op(parsed, &instruction)) return true;
    parsed.instructions[parsed.instruction_count] = instruction;
    parsed.instruction_count += 1;
    return true;
}

fn compute_text_layout(parsed: *Program) bool {
    // Pseudo-instructions can expand into multiple machine words.
    // We keep an explicit map from text-word index to source instruction index so
    // jumps, returns, and self-modifying text writes can resolve correctly.
    var word_index: u32 = 0;
    var instruction_index: u32 = 0;
    while (instruction_index < parsed.instruction_count) : (instruction_index += 1) {
        if (word_index >= max_text_word_count) return false;

        parsed.instruction_word_indices[instruction_index] = word_index;

        const instruction = parsed.instructions[instruction_index];
        const word_count = estimate_instruction_word_count(&instruction);
        if (word_count == 0) return false;
        if (word_index + word_count > max_text_word_count) return false;

        // Every expanded machine word maps back to the source instruction that produced it.
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
    // This count intentionally approximates MARS assembler expansion rules that
    // affect text addresses visible to runtime behavior.
    const op = instruction.op[0..instruction.op_len];

    if (std.mem.eql(u8, op, "li")) {
        if (instruction.operand_count != 2) return 1;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return 1;
        if (imm >= std.math.minInt(i16) and imm <= std.math.maxInt(i16)) return 1;
        if (imm >= 0 and imm <= std.math.maxInt(u16)) return 1;
        return 2;
    }

    if (std.mem.eql(u8, op, "la")) {
        if (instruction.operand_count != 2) return 1;
        return estimate_la_word_count(instruction_operand(instruction, 1));
    }

    if (std.mem.eql(u8, op, "blt") or
        std.mem.eql(u8, op, "bltu") or
        std.mem.eql(u8, op, "bge") or
        std.mem.eql(u8, op, "bgeu") or
        std.mem.eql(u8, op, "bgt") or
        std.mem.eql(u8, op, "bgtu") or
        std.mem.eql(u8, op, "ble") or
        std.mem.eql(u8, op, "bleu"))
    {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 1)) != null) return 2;

        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return 1;
        if (std.mem.eql(u8, op, "bgt") or
            std.mem.eql(u8, op, "bgtu") or
            std.mem.eql(u8, op, "ble") or
            std.mem.eql(u8, op, "bleu"))
        {
            if (immediate_fits_signed_16(imm)) return 3;
            return 4;
        }
        if (immediate_fits_signed_16(imm)) return 2;
        return 4;
    }

    if (std.mem.eql(u8, op, "beq") or std.mem.eql(u8, op, "bne")) {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 1)) != null) return 1;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 2;
        return 3;
    }

    if (std.mem.eql(u8, op, "addi") or std.mem.eql(u8, op, "addiu")) {
        if (instruction.operand_count != 3) return 1;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 1;
        return 3;
    }

    if (std.mem.eql(u8, op, "subi") or std.mem.eql(u8, op, "subiu")) {
        if (instruction.operand_count != 3) return 1;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 2;
        return 3;
    }

    if (std.mem.eql(u8, op, "andi") or std.mem.eql(u8, op, "ori") or std.mem.eql(u8, op, "xori")) {
        if (instruction.operand_count == 3) {
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
            if (immediate_fits_unsigned_16(imm)) return 1;
            return 3;
        }
        if (instruction.operand_count == 2) {
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return 1;
            if (immediate_fits_unsigned_16(imm)) return 1;
            return 3;
        }
        return 1;
    }

    if (std.mem.eql(u8, op, "abs")) {
        if (instruction.operand_count != 2) return 1;
        return 3;
    }

    if (std.mem.eql(u8, op, "mul")) {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 1;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 2;
        return 3;
    }

    if (std.mem.eql(u8, op, "mulo")) {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 7;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 8;
        return 9;
    }

    if (std.mem.eql(u8, op, "mulou")) {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 5;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 6;
        return 7;
    }

    if (std.mem.eql(u8, op, "div") or
        std.mem.eql(u8, op, "divu") or
        std.mem.eql(u8, op, "rem") or
        std.mem.eql(u8, op, "remu"))
    {
        if (instruction.operand_count == 2) return 1;
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 4;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 3;
        return 4;
    }

    if (std.mem.eql(u8, op, "ulw") or std.mem.eql(u8, op, "usw") or std.mem.eql(u8, op, "ld") or std.mem.eql(u8, op, "sd")) {
        if (instruction.operand_count != 2) return 1;
        return estimate_ulw_like_word_count(instruction_operand(instruction, 1));
    }

    if (std.mem.eql(u8, op, "ulh") or std.mem.eql(u8, op, "ulhu")) {
        if (instruction.operand_count != 2) return 1;
        return estimate_ulh_like_word_count(instruction_operand(instruction, 1));
    }

    if (std.mem.eql(u8, op, "ush")) {
        if (instruction.operand_count != 2) return 1;
        return estimate_ush_like_word_count(instruction_operand(instruction, 1));
    }

    if (std.mem.eql(u8, op, "lb") or
        std.mem.eql(u8, op, "lbu") or
        std.mem.eql(u8, op, "lh") or
        std.mem.eql(u8, op, "lhu") or
        std.mem.eql(u8, op, "lw") or
        std.mem.eql(u8, op, "ll") or
        std.mem.eql(u8, op, "ld") or
        std.mem.eql(u8, op, "sb") or
        std.mem.eql(u8, op, "sh") or
        std.mem.eql(u8, op, "sw") or
        std.mem.eql(u8, op, "sc") or
        std.mem.eql(u8, op, "sd") or
        std.mem.eql(u8, op, "lwl") or
        std.mem.eql(u8, op, "lwr") or
        std.mem.eql(u8, op, "swl") or
        std.mem.eql(u8, op, "swr") or
        std.mem.eql(u8, op, "l.s") or
        std.mem.eql(u8, op, "l.d") or
        std.mem.eql(u8, op, "s.s") or
        std.mem.eql(u8, op, "s.d") or
        std.mem.eql(u8, op, "lwc1") or
        std.mem.eql(u8, op, "ldc1") or
        std.mem.eql(u8, op, "swc1") or
        std.mem.eql(u8, op, "sdc1"))
    {
        if (instruction.operand_count < 2) return 1;
        return estimate_memory_operand_word_count(instruction_operand(instruction, 1));
    }

    if (std.mem.eql(u8, op, "add") or
        std.mem.eql(u8, op, "addu") or
        std.mem.eql(u8, op, "sub") or
        std.mem.eql(u8, op, "subu"))
    {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 1;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        return estimate_add_sub_immediate_word_count(op, imm);
    }

    if (std.mem.eql(u8, op, "seq") or
        std.mem.eql(u8, op, "sge") or
        std.mem.eql(u8, op, "sgeu") or
        std.mem.eql(u8, op, "sle") or
        std.mem.eql(u8, op, "sleu"))
    {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 3;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 4;
        return 5;
    }

    if (std.mem.eql(u8, op, "sne")) {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 2;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 3;
        return 4;
    }

    if (std.mem.eql(u8, op, "sgt") or std.mem.eql(u8, op, "sgtu")) {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 1;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 2;
        return 3;
    }

    if (std.mem.eql(u8, op, "rol") or std.mem.eql(u8, op, "ror")) {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 4;
        if (operand_parse.parse_immediate(instruction_operand(instruction, 2)) != null) return 3;
        return 1;
    }

    if (std.mem.eql(u8, op, "mfc1.d") or std.mem.eql(u8, op, "mtc1.d")) {
        if (instruction.operand_count != 2) return 1;
        return 2;
    }

    if (std.mem.eql(u8, op, "mulu")) {
        if (instruction.operand_count != 3) return 1;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 2;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 3;
        return 4;
    }

    return 1;
}

fn estimate_la_word_count(address_operand_text: []const u8) u32 {
    const address_operand = parse_address_operand(address_operand_text) orelse return 1;

    const has_base = address_operand.base_register != null;
    switch (address_operand.expression) {
        .empty => {
            if (has_base) return 1;
            return 1;
        },
        .immediate => |imm| {
            if (!has_base) {
                if (immediate_fits_signed_16(imm) or immediate_fits_unsigned_16(imm)) return 1;
                return 2;
            }
            if (immediate_fits_unsigned_16(imm)) return 2;
            return 3;
        },
        .label => {
            if (has_base) return 3;
            return 2;
        },
        .label_plus_offset => {
            if (has_base) return 3;
            return 2;
        },
        .invalid => return 1,
    }
}

fn estimate_memory_operand_word_count(address_operand_text: []const u8) u32 {
    const address_operand = parse_address_operand(address_operand_text) orelse return 1;

    const has_base = address_operand.base_register != null;
    switch (address_operand.expression) {
        .empty => {
            if (has_base) return 1;
            return 1;
        },
        .immediate => |imm| {
            if (!has_base) {
                if (immediate_fits_signed_16(imm)) return 1;
                return 2;
            }
            if (immediate_fits_signed_16(imm)) return 1;
            return 3;
        },
        .label => {
            if (has_base) return 3;
            return 2;
        },
        .label_plus_offset => {
            if (has_base) return 3;
            return 2;
        },
        .invalid => return 1,
    }
}

fn estimate_ulw_like_word_count(address_operand_text: []const u8) u32 {
    const address_operand = parse_address_operand(address_operand_text) orelse return 1;
    const has_base = address_operand.base_register != null;

    switch (address_operand.expression) {
        .empty => {
            if (has_base) return 2;
            return 1;
        },
        .immediate => |imm| {
            if (!has_base) return 4;
            if (immediate_fits_signed_16(imm)) return 4;
            return 6;
        },
        .label => {
            if (has_base) return 6;
            return 4;
        },
        .label_plus_offset => {
            if (has_base) return 6;
            return 4;
        },
        .invalid => return 1,
    }
}

fn estimate_ulh_like_word_count(address_operand_text: []const u8) u32 {
    const address_operand = parse_address_operand(address_operand_text) orelse return 1;
    const has_base = address_operand.base_register != null;

    switch (address_operand.expression) {
        .empty => {
            if (has_base) return 4;
            return 1;
        },
        .immediate => |imm| {
            if (!has_base) return 6;
            if (immediate_fits_signed_16(imm)) return 6;
            return 8;
        },
        .label => {
            if (has_base) return 8;
            return 6;
        },
        .label_plus_offset => {
            if (has_base) return 8;
            return 6;
        },
        .invalid => return 1,
    }
}

fn estimate_ush_like_word_count(address_operand_text: []const u8) u32 {
    const address_operand = parse_address_operand(address_operand_text) orelse return 1;
    const has_base = address_operand.base_register != null;

    switch (address_operand.expression) {
        .empty => {
            if (has_base) return 8;
            return 1;
        },
        .immediate => |imm| {
            if (!has_base) return 10;
            if (immediate_fits_signed_16(imm)) return 10;
            return 12;
        },
        .label => {
            if (has_base) return 12;
            return 10;
        },
        .label_plus_offset => {
            if (has_base) return 12;
            return 10;
        },
        .invalid => return 1,
    }
}

fn immediate_fits_signed_16(imm: i32) bool {
    return imm >= std.math.minInt(i16) and imm <= std.math.maxInt(i16);
}

fn immediate_fits_unsigned_16(imm: i32) bool {
    return imm >= 0 and imm <= std.math.maxInt(u16);
}

fn delay_slot_active(state: *const ExecState) bool {
    return state.delayed_branch_state == .triggered;
}

fn delay_slot_first_word_set_at_from_immediate(state: *ExecState, imm: i32) void {
    if (immediate_fits_signed_16(imm)) {
        write_reg(state, 1, imm);
        return;
    }
    const imm_bits: u32 = @bitCast(imm);
    const high_only: u32 = imm_bits & 0xFFFF_0000;
    write_reg(state, 1, @bitCast(high_only));
}

fn estimate_add_sub_immediate_word_count(op: []const u8, imm: i32) u32 {
    if (std.mem.eql(u8, op, "add")) {
        if (immediate_fits_signed_16(imm)) return 1;
        return 3;
    }

    if (std.mem.eql(u8, op, "sub")) {
        if (immediate_fits_signed_16(imm)) return 2;
        return 3;
    }

    // `addu`/`subu` immediate forms are handled as 32-bit pseudo expansions.
    return 3;
}

fn execute_program(
    parsed: *Program,
    output: []u8,
    output_len_bytes: *u32,
    options: EngineOptions,
) StatusCode {
    const state = &exec_state_storage;
    // Reinitialize full machine state for each run.
    state.* = .{
        .regs = init_integer_registers(),
        .fp_regs = [_]u32{0} ** 32,
        .fp_condition_flags = 0,
        .cp0_regs = [_]i32{0} ** 32,
        .hi = 0,
        .lo = 0,
        .pc = 0,
        .halted = false,
        .delayed_branching_enabled = options.delayed_branching_enabled,
        .smc_enabled = options.smc_enabled,
        .delayed_branch_state = .cleared,
        .delayed_branch_target = 0,
        .input_text = options.input_text,
        .input_offset_bytes = 0,
        .text_patch_words = [_]u32{0} ** max_instruction_count,
        .text_patch_valid = [_]bool{false} ** max_instruction_count,
        .heap = [_]u8{0} ** heap_capacity_bytes,
        .heap_len_bytes = 0,
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

    // Guard the interpreter loop to keep malformed programs from spinning forever.
    var run_step_count: u32 = 0;
    while (!state.halted) {
        if (state.pc >= parsed.instruction_count) {
            return .runtime_error;
        }
        if (run_step_count >= 200_000) {
            return .runtime_error;
        }
        run_step_count += 1;

        const current_pc = state.pc;
        state.pc += 1;

        var status: StatusCode = .ok;
        // If SMC patched this slot, execute the patched machine word.
        if (state.text_patch_valid[current_pc]) {
            const patched_word = state.text_patch_words[current_pc];
            status = execute_patched_instruction(
                parsed,
                state,
                current_pc,
                patched_word,
                output,
                output_len_bytes,
            );
        } else {
            const instruction = parsed.instructions[current_pc];
            status = execute_instruction(parsed, state, &instruction, output, output_len_bytes);
        }
        if (status != .ok) return status;

        // Delayed branch sequencing:
        // - `registered` means the current instruction set a delayed target.
        // - next cycle transitions to `triggered`.
        // - after executing the delay slot, jump and clear.
        if (state.delayed_branch_state == .triggered) {
            state.pc = state.delayed_branch_target;
            state.delayed_branch_state = .cleared;
            state.delayed_branch_target = 0;
        } else if (state.delayed_branch_state == .registered) {
            state.delayed_branch_state = .triggered;
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
    // Dispatch remains explicit and linear to keep behavior easy to diff against MARS.
    const op = instruction.op[0..instruction.op_len];

    // Pseudo-instruction group.
    if (std.mem.eql(u8, op, "li")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (delay_slot_active(state)) {
            // In a delay slot, only the first expanded machine word executes.
            if (!immediate_fits_signed_16(imm) and !immediate_fits_unsigned_16(imm)) {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
        }
        write_reg(state, rd, imm);
        return .ok;
    }

    if (std.mem.eql(u8, op, "move")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_reg(state, rd, read_reg(state, rs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "la")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        if (delay_slot_active(state)) {
            // Delay-slot behavior executes only the first expanded machine word.
            const address_operand = parse_address_operand(instruction_operand(instruction, 1)) orelse return .parse_error;
            switch (address_operand.expression) {
                .empty => {
                    const base_register = address_operand.base_register orelse return .parse_error;
                    // `la rd, (base)` first word is `addi rd, base, 0`.
                    write_reg(state, rd, read_reg(state, base_register));
                    return .ok;
                },
                .immediate => |imm| {
                    if (address_operand.base_register == null) {
                        // No-base form can be single-word sign/zero-extended immediate load.
                        if (immediate_fits_signed_16(imm) or immediate_fits_unsigned_16(imm)) {
                            write_reg(state, rd, imm);
                            return .ok;
                        }
                        const imm_bits: u32 = @bitCast(imm);
                        const high_only: u32 = imm_bits & 0xFFFF_0000;
                        write_reg(state, 1, @bitCast(high_only));
                        return .ok;
                    }
                    // Base+immediate form starts with loading immediate into `$at`.
                    if (immediate_fits_unsigned_16(imm)) {
                        write_reg(state, 1, imm);
                        return .ok;
                    }
                    const imm_bits: u32 = @bitCast(imm);
                    const high_only: u32 = imm_bits & 0xFFFF_0000;
                    write_reg(state, 1, @bitCast(high_only));
                    return .ok;
                },
                .label => |label_name| {
                    const label_address = resolve_label_address(parsed, label_name) orelse return .parse_error;
                    if (address_operand.base_register == null) {
                        // Compact no-base form is `addi rd, $zero, low(label)` when signed-16 fits.
                        const label_i32: i32 = @bitCast(label_address);
                        if (immediate_fits_signed_16(label_i32)) {
                            write_reg(state, rd, label_i32);
                            return .ok;
                        }
                    } else {
                        // Compact base form is `addi rd, base, low(label)` when signed-16 fits.
                        const label_i32: i32 = @bitCast(label_address);
                        if (immediate_fits_signed_16(label_i32)) {
                            const base_register = address_operand.base_register.?;
                            const lhs = read_reg(state, base_register);
                            const sum = lhs +% label_i32;
                            if (signed_add_overflow(lhs, label_i32, sum)) return .runtime_error;
                            write_reg(state, rd, sum);
                            return .ok;
                        }
                    }
                    const high_only: u32 = label_address & 0xFFFF_0000;
                    write_reg(state, 1, @bitCast(high_only));
                    return .ok;
                },
                .label_plus_offset => |label_offset| {
                    const label_address = resolve_label_address(parsed, label_offset.label_name) orelse return .parse_error;
                    const full_address = label_address +% @as(u32, @bitCast(label_offset.offset));
                    // `label+offset` forms always start with `lui $at, high(...)`.
                    const high_only: u32 = full_address & 0xFFFF_0000;
                    write_reg(state, 1, @bitCast(high_only));
                    return .ok;
                },
                .invalid => return .parse_error,
            }
        }
        const address = resolve_address_operand(
            parsed,
            state,
            instruction_operand(instruction, 1),
        ) orelse return .parse_error;
        write_reg(state, rd, @bitCast(address));
        return .ok;
    }

    if (std.mem.eql(u8, op, "l.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value = read_u32_be(parsed, address) orelse return .runtime_error;
        write_fp_single(state, fd, value);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lwc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((address & 3) != 0) return .runtime_error;
        const value = read_u32_be(parsed, address) orelse return .runtime_error;
        write_fp_single(state, fd, value);
        return .ok;
    }

    if (std.mem.eql(u8, op, "l.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        const address = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((address & 7) != 0) return .runtime_error;
        const value = read_u64_be(parsed, address) orelse return .runtime_error;
        write_fp_double(state, fd, value);
        return .ok;
    }

    if (std.mem.eql(u8, op, "ldc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        const address = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((address & 7) != 0) return .runtime_error;
        const value_low = read_u32_be(parsed, address) orelse return .runtime_error;
        const value_high = read_u32_be(parsed, address + 4) orelse return .runtime_error;
        write_fp_single(state, fd, value_low);
        write_fp_single(state, fd + 1, value_high);
        return .ok;
    }

    // Load/store group.
    if (std.mem.eql(u8, op, "lb")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value_u8 = read_u8(parsed, addr) orelse return .runtime_error;
        const value_i8: i8 = @bitCast(value_u8);
        write_reg(state, rt, value_i8);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lbu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value_u8 = read_u8(parsed, addr) orelse return .runtime_error;
        write_reg(state, rt, value_u8);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lh")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 1) != 0) return .runtime_error;
        const value_u16 = read_u16_be(parsed, addr) orelse return .runtime_error;
        const value_i16: i16 = @bitCast(value_u16);
        write_reg(state, rt, value_i16);
        return .ok;
    }

    if (std.mem.eql(u8, op, "ulh")) {
        // Unaligned halfword load pseudo-op.
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value_u16 = read_u16_be(parsed, addr) orelse return .runtime_error;
        const value_i16: i16 = @bitCast(value_u16);
        write_reg(state, rt, value_i16);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lhu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 1) != 0) return .runtime_error;
        const value_u16 = read_u16_be(parsed, addr) orelse return .runtime_error;
        write_reg(state, rt, value_u16);
        return .ok;
    }

    if (std.mem.eql(u8, op, "ulhu")) {
        // Unaligned unsigned halfword load pseudo-op.
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value_u16 = read_u16_be(parsed, addr) orelse return .runtime_error;
        write_reg(state, rt, value_u16);
        return .ok;
    }

    if (std.mem.eql(u8, op, "lw")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const value = read_u32_be(parsed, addr) orelse return .runtime_error;
        write_reg(state, rt, @bitCast(value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ulw")) {
        // Unaligned word load pseudo-op.
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value = read_u32_be(parsed, addr) orelse return .runtime_error;
        write_reg(state, rt, @bitCast(value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ld")) {
        // Pseudo-op doubleword load into a register pair (rt, rt+1).
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        if (rt >= 31) return .runtime_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const low = read_u32_be(parsed, addr) orelse return .runtime_error;
        const high = read_u32_be(parsed, addr + 4) orelse return .runtime_error;
        write_reg(state, rt, @bitCast(low));
        write_reg(state, rt + 1, @bitCast(high));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ll")) {
        // MARS models LL as LW because it does not simulate multi-core interference.
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const value = read_u32_be(parsed, addr) orelse return .runtime_error;
        write_reg(state, rt, @bitCast(value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "lwl")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        var result: u32 = @bitCast(read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= mod_u2) : (i += 1) {
            const source_byte = read_u8(parsed, address - i) orelse return .runtime_error;
            const byte_index: u2 = @intCast(3 - i);
            result = fp_math.int_set_byte(result, byte_index, source_byte);
        }
        write_reg(state, rt, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "lwr")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        var result: u32 = @bitCast(read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= @as(u2, 3 - mod_u2)) : (i += 1) {
            const source_byte = read_u8(parsed, address + i) orelse return .runtime_error;
            result = fp_math.int_set_byte(result, i, source_byte);
        }
        write_reg(state, rt, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sb")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u8(parsed, addr, @intCast(value & 0xFF))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sh")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 1) != 0) return .runtime_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u16_be(parsed, addr, @intCast(value & 0xFFFF))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "ush")) {
        // Unaligned halfword store pseudo-op.
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u8(parsed, addr, @intCast(value & 0xFF))) return .runtime_error;
        if (!write_u8(parsed, addr + 1, @intCast((value >> 8) & 0xFF))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sw")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u32(parsed, state, addr, value)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "usw")) {
        // Unaligned word store pseudo-op.
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u8(parsed, addr, @intCast(value & 0xFF))) return .runtime_error;
        if (!write_u8(parsed, addr + 1, @intCast((value >> 8) & 0xFF))) return .runtime_error;
        if (!write_u8(parsed, addr + 2, @intCast((value >> 16) & 0xFF))) return .runtime_error;
        if (!write_u8(parsed, addr + 3, @intCast((value >> 24) & 0xFF))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sd")) {
        // Pseudo-op doubleword store from a register pair (rt, rt+1).
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        if (rt >= 31) return .runtime_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const low: u32 = @bitCast(read_reg(state, rt));
        const high: u32 = @bitCast(read_reg(state, rt + 1));
        if (!write_u32(parsed, state, addr, low)) return .runtime_error;
        if (!write_u32(parsed, state, addr + 4, high)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "swc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        if (!write_u32(parsed, state, addr, read_fp_single(state, ft))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sdc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(ft)) return .runtime_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 7) != 0) return .runtime_error;
        if (!write_u32(parsed, state, addr, read_fp_single(state, ft))) return .runtime_error;
        if (!write_u32(parsed, state, addr + 4, read_fp_single(state, ft + 1))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "s.s")) {
        // Pseudo-op alias for `swc1`.
        if (instruction.operand_count != 2) return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        if (!write_u32(parsed, state, addr, read_fp_single(state, ft))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "s.d")) {
        // Pseudo-op alias for `sdc1`.
        if (instruction.operand_count != 2) return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(ft)) return .runtime_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 7) != 0) return .runtime_error;
        if (!write_u32(parsed, state, addr, read_fp_single(state, ft))) return .runtime_error;
        if (!write_u32(parsed, state, addr + 4, read_fp_single(state, ft + 1))) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "sc")) {
        // MARS models SC as SW followed by writing success (1) into source register.
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const addr = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        if ((addr & 3) != 0) return .runtime_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u32(parsed, state, addr, value)) return .runtime_error;
        write_reg(state, rt, 1);
        return .ok;
    }

    if (std.mem.eql(u8, op, "swl")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const source: u32 = @bitCast(read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= mod_u2) : (i += 1) {
            const byte_index: u2 = @intCast(3 - i);
            if (!write_u8(parsed, address - i, fp_math.int_get_byte(source, byte_index))) return .runtime_error;
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "swr")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const address = resolve_load_address(parsed, state, instruction_operand(instruction, 1)) orelse return .parse_error;
        const source: u32 = @bitCast(read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= @as(u2, 3 - mod_u2)) : (i += 1) {
            if (!write_u8(parsed, address + i, fp_math.int_get_byte(source, i))) return .runtime_error;
        }
        return .ok;
    }

    // Integer arithmetic and logical group.
    if (std.mem.eql(u8, op, "add")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (operand_parse.parse_register(instruction_operand(instruction, 2))) |rt| {
            const lhs = read_reg(state, rs);
            const rhs = read_reg(state, rt);
            const sum = lhs +% rhs;
            if (signed_add_overflow(lhs, rhs, sum)) return .runtime_error;
            write_reg(state, rd, sum);
            return .ok;
        }
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (delay_slot_active(state)) {
            if (immediate_fits_signed_16(imm)) {
                // 16-bit pseudo form first word is `addi rd, rs, imm`.
                const lhs = read_reg(state, rs);
                const sum = lhs +% imm;
                if (signed_add_overflow(lhs, imm, sum)) return .runtime_error;
                write_reg(state, rd, sum);
                return .ok;
            }
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            const imm_bits: u32 = @bitCast(imm);
            const high_only: u32 = imm_bits & 0xFFFF_0000;
            write_reg(state, 1, @bitCast(high_only));
            return .ok;
        }
        const lhs = read_reg(state, rs);
        const sum = lhs +% imm;
        if (signed_add_overflow(lhs, imm, sum)) return .runtime_error;
        write_reg(state, rd, sum);
        return .ok;
    }

    if (std.mem.eql(u8, op, "addi")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (delay_slot_active(state) and !immediate_fits_signed_16(imm)) {
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            const imm_bits: u32 = @bitCast(imm);
            const high_only: u32 = imm_bits & 0xFFFF_0000;
            write_reg(state, 1, @bitCast(high_only));
            return .ok;
        }
        const lhs = read_reg(state, rs);
        const sum = lhs +% imm;
        if (signed_add_overflow(lhs, imm, sum)) return .runtime_error;
        write_reg(state, rt, sum);
        return .ok;
    }

    if (std.mem.eql(u8, op, "subi")) {
        // Pseudo-op alias for addi with negated immediate.
        if (instruction.operand_count != 3) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (delay_slot_active(state)) {
            if (immediate_fits_signed_16(imm)) {
                // 16-bit pseudo form first word is `addi $at, $zero, imm`.
                write_reg(state, 1, imm);
                return .ok;
            }
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            const imm_bits: u32 = @bitCast(imm);
            const high_only: u32 = imm_bits & 0xFFFF_0000;
            write_reg(state, 1, @bitCast(high_only));
            return .ok;
        }
        const neg_imm = -%imm;
        const lhs = read_reg(state, rs);
        const sum = lhs +% neg_imm;
        if (signed_add_overflow(lhs, neg_imm, sum)) return .runtime_error;
        write_reg(state, rt, sum);
        return .ok;
    }

    if (std.mem.eql(u8, op, "addu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (operand_parse.parse_register(instruction_operand(instruction, 2))) |rt| {
            write_reg(state, rd, read_reg(state, rs) +% read_reg(state, rt));
            return .ok;
        }
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (delay_slot_active(state)) {
            // Immediate pseudo form first word is always `lui $at, high(imm)`.
            const imm_bits: u32 = @bitCast(imm);
            const high_only: u32 = imm_bits & 0xFFFF_0000;
            write_reg(state, 1, @bitCast(high_only));
            return .ok;
        }
        write_reg(state, rd, read_reg(state, rs) +% imm);
        return .ok;
    }

    if (std.mem.eql(u8, op, "sub")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state) and operand_parse.parse_register(rhs_operand) == null) {
            const imm = operand_parse.parse_immediate(rhs_operand) orelse return .parse_error;
            if (immediate_fits_signed_16(imm)) {
                // 16-bit pseudo form first word is `addi $at, $zero, imm`.
                write_reg(state, 1, imm);
                return .ok;
            }
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            const imm_bits: u32 = @bitCast(imm);
            const high_only: u32 = imm_bits & 0xFFFF_0000;
            write_reg(state, 1, @bitCast(high_only));
            return .ok;
        }
        const rhs = if (operand_parse.parse_register(rhs_operand)) |rt|
            read_reg(state, rt)
        else
            operand_parse.parse_immediate(rhs_operand) orelse return .parse_error;
        const lhs = read_reg(state, rs);
        const dif = lhs -% rhs;
        if (signed_sub_overflow(lhs, rhs, dif)) return .runtime_error;
        write_reg(state, rd, dif);
        return .ok;
    }

    if (std.mem.eql(u8, op, "subu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (delay_slot_active(state) and operand_parse.parse_register(instruction_operand(instruction, 2)) == null) {
            // Immediate pseudo form first word is always `lui $at, high(imm)`.
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
            const imm_bits: u32 = @bitCast(imm);
            const high_only: u32 = imm_bits & 0xFFFF_0000;
            write_reg(state, 1, @bitCast(high_only));
            return .ok;
        }
        const rhs = if (operand_parse.parse_register(instruction_operand(instruction, 2))) |rt|
            read_reg(state, rt)
        else
            operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        write_reg(state, rd, read_reg(state, rs) -% rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "addiu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (delay_slot_active(state) and !immediate_fits_signed_16(imm)) {
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            const imm_bits: u32 = @bitCast(imm);
            const high_only: u32 = imm_bits & 0xFFFF_0000;
            write_reg(state, 1, @bitCast(high_only));
            return .ok;
        }
        write_reg(state, rt, read_reg(state, rs) +% imm);
        return .ok;
    }

    if (std.mem.eql(u8, op, "subiu")) {
        // Pseudo-op alias for 32-bit immediate subtraction without overflow trap.
        if (instruction.operand_count != 3) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (delay_slot_active(state)) {
            // Immediate pseudo form first word is always `lui $at, high(imm)`.
            const imm_bits: u32 = @bitCast(imm);
            const high_only: u32 = imm_bits & 0xFFFF_0000;
            write_reg(state, 1, @bitCast(high_only));
            return .ok;
        }
        write_reg(state, rt, read_reg(state, rs) -% imm);
        return .ok;
    }

    if (std.mem.eql(u8, op, "and")) {
        if (instruction.operand_count == 3) {
            const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rs));
            if (operand_parse.parse_register(instruction_operand(instruction, 2))) |rt| {
                const rhs: u32 = @bitCast(read_reg(state, rt));
                write_reg(state, rd, @bitCast(lhs & rhs));
                return .ok;
            }
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rd, @bitCast(lhs & imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rd, @bitCast(lhs & rhs));
            return .ok;
        }
        if (instruction.operand_count == 2) {
            const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rd));
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rd, @bitCast(lhs & imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rd, @bitCast(lhs & rhs));
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "or")) {
        if (instruction.operand_count == 3) {
            const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rs));
            if (operand_parse.parse_register(instruction_operand(instruction, 2))) |rt| {
                const rhs: u32 = @bitCast(read_reg(state, rt));
                write_reg(state, rd, @bitCast(lhs | rhs));
                return .ok;
            }
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rd, @bitCast(lhs | imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rd, @bitCast(lhs | rhs));
            return .ok;
        }
        if (instruction.operand_count == 2) {
            const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rd));
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rd, @bitCast(lhs | imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rd, @bitCast(lhs | rhs));
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "andi")) {
        if (instruction.operand_count == 3) {
            const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rs));
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rt, @bitCast(lhs & imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rt, @bitCast(lhs & rhs));
            return .ok;
        }
        if (instruction.operand_count == 2) {
            const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rt));
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rt, @bitCast(lhs & imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rt, @bitCast(lhs & rhs));
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "ori")) {
        if (instruction.operand_count == 3) {
            const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rs));
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rt, @bitCast(lhs | imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rt, @bitCast(lhs | rhs));
            return .ok;
        }
        if (instruction.operand_count == 2) {
            const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rt));
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rt, @bitCast(lhs | imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rt, @bitCast(lhs | rhs));
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "xor")) {
        if (instruction.operand_count == 3) {
            const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rs));
            if (operand_parse.parse_register(instruction_operand(instruction, 2))) |rt| {
                const rhs: u32 = @bitCast(read_reg(state, rt));
                write_reg(state, rd, @bitCast(lhs ^ rhs));
                return .ok;
            }
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rd, @bitCast(lhs ^ imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rd, @bitCast(lhs ^ rhs));
            return .ok;
        }
        if (instruction.operand_count == 2) {
            const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rd));
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rd, @bitCast(lhs ^ imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rd, @bitCast(lhs ^ rhs));
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "xori")) {
        if (instruction.operand_count == 3) {
            const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rs));
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rt, @bitCast(lhs ^ imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rt, @bitCast(lhs ^ rhs));
            return .ok;
        }
        if (instruction.operand_count == 2) {
            const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const lhs: u32 = @bitCast(read_reg(state, rt));
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return .parse_error;
            if (delay_slot_active(state)) {
                if (immediate_fits_unsigned_16(imm)) {
                    const imm16: u32 = @intCast(imm);
                    write_reg(state, rt, @bitCast(lhs ^ imm16));
                    return .ok;
                }
                const imm_bits: u32 = @bitCast(imm);
                const high_only: u32 = imm_bits & 0xFFFF_0000;
                write_reg(state, 1, @bitCast(high_only));
                return .ok;
            }
            const rhs: u32 = if (immediate_fits_unsigned_16(imm))
                @intCast(imm)
            else
                @bitCast(imm);
            write_reg(state, rt, @bitCast(lhs ^ rhs));
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "nor")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(~(lhs | rhs)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sll")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const shamt_i32 = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
        const shamt: u5 = @intCast(shamt_i32);
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(rhs << shamt));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sllv")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const shamt: u5 = @intCast(@as(u32, @bitCast(read_reg(state, rs))) & 0x1F);
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(rhs << shamt));
        return .ok;
    }

    if (std.mem.eql(u8, op, "srl")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const shamt_i32 = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
        const shamt: u5 = @intCast(shamt_i32);
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(rhs >> shamt));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sra")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const shamt_i32 = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
        const shamt: u5 = @intCast(shamt_i32);
        write_reg(state, rd, read_reg(state, rt) >> shamt);
        return .ok;
    }

    if (std.mem.eql(u8, op, "srav")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const shamt: u5 = @intCast(@as(u32, @bitCast(read_reg(state, rs))) & 0x1F);
        write_reg(state, rd, read_reg(state, rt) >> shamt);
        return .ok;
    }

    if (std.mem.eql(u8, op, "srlv")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const shamt: u5 = @intCast(@as(u32, @bitCast(read_reg(state, rs))) & 0x1F);
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(rhs >> shamt));
        return .ok;
    }

    if (std.mem.eql(u8, op, "rol")) {
        // Rotate-left pseudo-op with immediate or register shift count.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            if (operand_parse.parse_register(rhs_operand)) |rs| {
                // Register form first word is `subu $at, $zero, rs`.
                write_reg(state, 1, 0 -% read_reg(state, rs));
                return .ok;
            }
            const shamt_i32 = operand_parse.parse_immediate(rhs_operand) orelse return .parse_error;
            if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
            const shift_i32 = 32 - shamt_i32;
            if (shift_i32 == 32) {
                write_reg(state, 1, 0);
                return .ok;
            }
            const shift: u5 = @intCast(shift_i32);
            const value: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, 1, @bitCast(value >> shift));
            return .ok;
        }
        const shamt: u5 = if (operand_parse.parse_register(rhs_operand)) |rs|
            @intCast(@as(u32, @bitCast(read_reg(state, rs))) & 0x1F)
        else blk: {
            const shamt_i32 = operand_parse.parse_immediate(rhs_operand) orelse return .parse_error;
            if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
            break :blk @intCast(shamt_i32);
        };
        const value: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(std.math.rotl(u32, value, shamt)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ror")) {
        // Rotate-right pseudo-op with immediate or register shift count.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            if (operand_parse.parse_register(rhs_operand)) |rs| {
                // Register form first word is `subu $at, $zero, rs`.
                write_reg(state, 1, 0 -% read_reg(state, rs));
                return .ok;
            }
            const shamt_i32 = operand_parse.parse_immediate(rhs_operand) orelse return .parse_error;
            if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
            const shift_i32 = 32 - shamt_i32;
            if (shift_i32 == 32) {
                write_reg(state, 1, 0);
                return .ok;
            }
            const shift: u5 = @intCast(shift_i32);
            const value: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, 1, @bitCast(value << shift));
            return .ok;
        }
        const shamt: u5 = if (operand_parse.parse_register(rhs_operand)) |rs|
            @intCast(@as(u32, @bitCast(read_reg(state, rs))) & 0x1F)
        else blk: {
            const shamt_i32 = operand_parse.parse_immediate(rhs_operand) orelse return .parse_error;
            if (shamt_i32 < 0 or shamt_i32 > 31) return .parse_error;
            break :blk @intCast(shamt_i32);
        };
        const value: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, @bitCast(std.math.rotr(u32, value, shamt)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mult")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: i64 = read_reg(state, rs);
        const rhs: i64 = read_reg(state, rt);
        const product: i64 = lhs * rhs;
        state.lo = @intCast(product & 0xFFFF_FFFF);
        state.hi = @intCast((product >> 32) & 0xFFFF_FFFF);
        return .ok;
    }

    if (std.mem.eql(u8, op, "multu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u64 = @intCast(@as(u32, @bitCast(read_reg(state, rs))));
        const rhs: u64 = @intCast(@as(u32, @bitCast(read_reg(state, rt))));
        const product: u64 = lhs * rhs;
        state.lo = @bitCast(@as(u32, @intCast(product & 0xFFFF_FFFF)));
        state.hi = @bitCast(@as(u32, @intCast((product >> 32) & 0xFFFF_FFFF)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mul")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state) and operand_parse.parse_register(rhs_operand) == null) {
            const imm = operand_parse.parse_immediate(rhs_operand) orelse return .parse_error;
            if (immediate_fits_signed_16(imm)) {
                // 16-bit pseudo form first word is `addi $at, $zero, imm`.
                write_reg(state, 1, imm);
                return .ok;
            }
            // 32-bit pseudo form first word is `lui $at, high(imm)`.
            const imm_bits: u32 = @bitCast(imm);
            const high_only: u32 = imm_bits & 0xFFFF_0000;
            write_reg(state, 1, @bitCast(high_only));
            return .ok;
        }
        const rhs = if (operand_parse.parse_register(rhs_operand)) |rt|
            read_reg(state, rt)
        else
            operand_parse.parse_immediate(rhs_operand) orelse return .parse_error;
        const product: i64 = @as(i64, read_reg(state, rs)) * @as(i64, rhs);
        state.hi = @intCast((product >> 32) & 0xFFFF_FFFF);
        state.lo = @intCast(product & 0xFFFF_FFFF);
        write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mulu")) {
        // Pseudo-op alias for unsigned multiply low result with HI/LO side effects.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                const lhs: u64 = @intCast(@as(u32, @bitCast(read_reg(state, rs))));
                const rhs: u64 = @intCast(@as(u32, @bitCast(read_reg(state, rt))));
                const product = lhs * rhs;
                state.hi = @bitCast(@as(u32, @truncate(product >> 32)));
                state.lo = @bitCast(@as(u32, @truncate(product)));
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        const lhs: u64 = @intCast(@as(u32, @bitCast(read_reg(state, rs))));
        const rhs: u64 = if (operand_parse.parse_register(rhs_operand)) |rt|
            @intCast(@as(u32, @bitCast(read_reg(state, rt))))
        else if (operand_parse.parse_immediate(rhs_operand)) |imm|
            @intCast(@as(u32, @bitCast(imm)))
        else
            return .parse_error;
        const product = lhs * rhs;
        state.hi = @bitCast(@as(u32, @truncate(product >> 32)));
        state.lo = @bitCast(@as(u32, @truncate(product)));
        write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mulo")) {
        // Signed multiply with overflow trap.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                const product: i64 = @as(i64, read_reg(state, rs)) * @as(i64, read_reg(state, rt));
                state.hi = @intCast((product >> 32) & 0xFFFF_FFFF);
                state.lo = @intCast(product & 0xFFFF_FFFF);
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        const rhs: i64 = if (operand_parse.parse_register(rhs_operand)) |rt|
            @as(i64, read_reg(state, rt))
        else if (operand_parse.parse_immediate(rhs_operand)) |imm|
            @as(i64, imm)
        else
            return .parse_error;
        const product: i64 = @as(i64, read_reg(state, rs)) * rhs;
        if (product < std.math.minInt(i32) or product > std.math.maxInt(i32)) return .runtime_error;
        state.hi = @intCast((product >> 32) & 0xFFFF_FFFF);
        state.lo = @intCast(product & 0xFFFF_FFFF);
        write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mulou")) {
        // Unsigned multiply with overflow trap.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                const lhs: u64 = @intCast(@as(u32, @bitCast(read_reg(state, rs))));
                const rhs: u64 = @intCast(@as(u32, @bitCast(read_reg(state, rt))));
                const product = lhs * rhs;
                state.hi = @bitCast(@as(u32, @truncate(product >> 32)));
                state.lo = @bitCast(@as(u32, @truncate(product)));
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        const lhs: u64 = @intCast(@as(u32, @bitCast(read_reg(state, rs))));
        const rhs: u64 = if (operand_parse.parse_register(rhs_operand)) |rt|
            @intCast(@as(u32, @bitCast(read_reg(state, rt))))
        else if (operand_parse.parse_immediate(rhs_operand)) |imm|
            @intCast(@as(u32, @bitCast(imm)))
        else
            return .parse_error;
        const product = lhs * rhs;
        if ((product >> 32) != 0) return .runtime_error;
        state.hi = 0;
        state.lo = @bitCast(@as(u32, @truncate(product)));
        write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "madd")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const product: i64 = @as(i64, read_reg(state, rs)) * @as(i64, read_reg(state, rt));
        const hi_bits: u32 = @bitCast(state.hi);
        const lo_bits: u32 = @bitCast(state.lo);
        const hilo_bits: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
        const hilo_signed: i64 = @bitCast(hilo_bits);
        const sum = hilo_signed +% product;
        const sum_bits: u64 = @bitCast(sum);
        state.hi = @bitCast(@as(u32, @intCast((sum_bits >> 32) & 0xFFFF_FFFF)));
        state.lo = @bitCast(@as(u32, @intCast(sum_bits & 0xFFFF_FFFF)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "maddu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const product: u64 = @as(u64, @intCast(@as(u32, @bitCast(read_reg(state, rs))))) *
            @as(u64, @intCast(@as(u32, @bitCast(read_reg(state, rt)))));
        const hi_bits: u32 = @bitCast(state.hi);
        const lo_bits: u32 = @bitCast(state.lo);
        const hilo: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
        const sum = hilo +% product;
        state.hi = @bitCast(@as(u32, @intCast((sum >> 32) & 0xFFFF_FFFF)));
        state.lo = @bitCast(@as(u32, @intCast(sum & 0xFFFF_FFFF)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "msub")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const product: i64 = @as(i64, read_reg(state, rs)) * @as(i64, read_reg(state, rt));
        const hi_bits: u32 = @bitCast(state.hi);
        const lo_bits: u32 = @bitCast(state.lo);
        const hilo_bits: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
        const hilo_signed: i64 = @bitCast(hilo_bits);
        const sum = hilo_signed -% product;
        const sum_bits: u64 = @bitCast(sum);
        state.hi = @bitCast(@as(u32, @intCast((sum_bits >> 32) & 0xFFFF_FFFF)));
        state.lo = @bitCast(@as(u32, @intCast(sum_bits & 0xFFFF_FFFF)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "msubu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const product: u64 = @as(u64, @intCast(@as(u32, @bitCast(read_reg(state, rs))))) *
            @as(u64, @intCast(@as(u32, @bitCast(read_reg(state, rt)))));
        const hi_bits: u32 = @bitCast(state.hi);
        const lo_bits: u32 = @bitCast(state.lo);
        const hilo: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
        const sum = hilo -% product;
        state.hi = @bitCast(@as(u32, @intCast((sum >> 32) & 0xFFFF_FFFF)));
        state.lo = @bitCast(@as(u32, @intCast(sum & 0xFFFF_FFFF)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "div")) {
        if (instruction.operand_count == 2) {
            const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
            const divisor = read_reg(state, rt);
            if (divisor == 0) return .ok;
            const dividend = read_reg(state, rs);
            state.lo = @divTrunc(dividend, divisor);
            state.hi = @rem(dividend, divisor);
            return .ok;
        }
        if (instruction.operand_count == 3) {
            // Pseudo-op alias. MARS traps on register zero-divisor form, but
            // immediate form expands to raw `div` and therefore keeps HI/LO
            // unchanged on zero divisor.
            const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
            const rhs_operand = instruction_operand(instruction, 2);
            if (delay_slot_active(state)) {
                // Register form first word is `bne rhs, $zero, ...`; no register/HI/LO writes.
                if (operand_parse.parse_register(rhs_operand) != null) return .ok;
                // Immediate forms begin with `$at` load in the first expanded word.
                if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                    delay_slot_first_word_set_at_from_immediate(state, imm);
                    return .ok;
                }
            }
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                const divisor = read_reg(state, rt);
                if (divisor == 0) return .runtime_error;
                const dividend = read_reg(state, rs);
                state.lo = @divTrunc(dividend, divisor);
                state.hi = @rem(dividend, divisor);
                write_reg(state, rd, state.lo);
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                if (imm != 0) {
                    const dividend = read_reg(state, rs);
                    state.lo = @divTrunc(dividend, imm);
                    state.hi = @rem(dividend, imm);
                }
                write_reg(state, rd, state.lo);
                return .ok;
            }
            return .parse_error;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "divu")) {
        if (instruction.operand_count == 2) {
            const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
            const divisor: u32 = @bitCast(read_reg(state, rt));
            if (divisor == 0) return .ok;
            const dividend: u32 = @bitCast(read_reg(state, rs));
            state.lo = @bitCast(dividend / divisor);
            state.hi = @bitCast(dividend % divisor);
            return .ok;
        }
        if (instruction.operand_count == 3) {
            // Pseudo-op alias with register-form zero-divisor trap semantics.
            const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
            const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
            const rhs_operand = instruction_operand(instruction, 2);
            if (delay_slot_active(state)) {
                // Register form first word is `bne rhs, $zero, ...`; no register/HI/LO writes.
                if (operand_parse.parse_register(rhs_operand) != null) return .ok;
                // Immediate forms begin with `$at` load in the first expanded word.
                if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                    delay_slot_first_word_set_at_from_immediate(state, imm);
                    return .ok;
                }
            }
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                const divisor: u32 = @bitCast(read_reg(state, rt));
                if (divisor == 0) return .runtime_error;
                const dividend: u32 = @bitCast(read_reg(state, rs));
                state.lo = @bitCast(dividend / divisor);
                state.hi = @bitCast(dividend % divisor);
                write_reg(state, rd, state.lo);
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                const divisor: u32 = @bitCast(imm);
                if (divisor != 0) {
                    const dividend: u32 = @bitCast(read_reg(state, rs));
                    state.lo = @bitCast(dividend / divisor);
                    state.hi = @bitCast(dividend % divisor);
                }
                write_reg(state, rd, state.lo);
                return .ok;
            }
            return .parse_error;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "rem")) {
        // Pseudo-op alias. Mirrors MARS expansion through `div` + `mfhi`.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // Register form first word is `bne rhs, $zero, ...`; no register/HI/LO writes.
            if (operand_parse.parse_register(rhs_operand) != null) return .ok;
            // Immediate forms begin with `$at` load in the first expanded word.
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
        }
        if (operand_parse.parse_register(rhs_operand)) |rt| {
            const divisor = read_reg(state, rt);
            if (divisor == 0) return .runtime_error;
            const dividend = read_reg(state, rs);
            state.lo = @divTrunc(dividend, divisor);
            state.hi = @rem(dividend, divisor);
            write_reg(state, rd, state.hi);
            return .ok;
        }
        if (operand_parse.parse_immediate(rhs_operand)) |imm| {
            if (imm != 0) {
                const dividend = read_reg(state, rs);
                state.lo = @divTrunc(dividend, imm);
                state.hi = @rem(dividend, imm);
            }
            write_reg(state, rd, state.hi);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "remu")) {
        // Pseudo-op alias. Mirrors MARS expansion through `divu` + `mfhi`.
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // Register form first word is `bne rhs, $zero, ...`; no register/HI/LO writes.
            if (operand_parse.parse_register(rhs_operand) != null) return .ok;
            // Immediate forms begin with `$at` load in the first expanded word.
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
        }
        if (operand_parse.parse_register(rhs_operand)) |rt| {
            const divisor: u32 = @bitCast(read_reg(state, rt));
            if (divisor == 0) return .runtime_error;
            const dividend: u32 = @bitCast(read_reg(state, rs));
            state.lo = @bitCast(dividend / divisor);
            state.hi = @bitCast(dividend % divisor);
            write_reg(state, rd, state.hi);
            return .ok;
        }
        if (operand_parse.parse_immediate(rhs_operand)) |imm| {
            const divisor: u32 = @bitCast(imm);
            if (divisor != 0) {
                const dividend: u32 = @bitCast(read_reg(state, rs));
                state.lo = @bitCast(dividend / divisor);
                state.hi = @bitCast(dividend % divisor);
            }
            write_reg(state, rd, state.hi);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "mflo")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        write_reg(state, rd, state.lo);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mfhi")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        write_reg(state, rd, state.hi);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mthi")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        state.hi = read_reg(state, rs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mtlo")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        state.lo = read_reg(state, rs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "clz")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(read_reg(state, rs));
        write_reg(state, rd, @intCast(@clz(value)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "clo")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: u32 = @bitCast(read_reg(state, rs));
        write_reg(state, rd, @intCast(@clz(~value)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "slt")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        write_reg(state, rd, if (read_reg(state, rs) < read_reg(state, rt)) 1 else 0);
        return .ok;
    }

    if (std.mem.eql(u8, op, "sltu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        write_reg(state, rd, if (lhs < rhs) 1 else 0);
        return .ok;
    }

    if (std.mem.eql(u8, op, "slti")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = operand_parse.parse_signed_imm16(instruction_operand(instruction, 2)) orelse return .parse_error;
        write_reg(state, rt, if (read_reg(state, rs) < imm) 1 else 0);
        return .ok;
    }

    if (std.mem.eql(u8, op, "sltiu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const imm = operand_parse.parse_signed_imm16(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(imm);
        write_reg(state, rt, if (lhs < rhs) 1 else 0);
        return .ok;
    }

    if (std.mem.eql(u8, op, "seq")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // `seq` first expansion word is `subu rd, rs, rhs`.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                write_reg(state, rd, read_reg(state, rs) -% read_reg(state, rt));
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (operand_parse.parse_register(rhs_operand)) |rt| {
            write_reg(state, rd, if (read_reg(state, rs) == read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (operand_parse.parse_immediate(rhs_operand)) |imm| {
            write_reg(state, rd, if (read_reg(state, rs) == imm) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sne")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // `sne` first expansion word is `subu rd, rs, rhs`.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                write_reg(state, rd, read_reg(state, rs) -% read_reg(state, rt));
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (operand_parse.parse_register(rhs_operand)) |rt| {
            write_reg(state, rd, if (read_reg(state, rs) != read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (operand_parse.parse_immediate(rhs_operand)) |imm| {
            write_reg(state, rd, if (read_reg(state, rs) != imm) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sge")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // `sge` first expansion word is `slt rd, rs, rhs`.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                write_reg(state, rd, if (read_reg(state, rs) < read_reg(state, rt)) 1 else 0);
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (operand_parse.parse_register(rhs_operand)) |rt| {
            write_reg(state, rd, if (read_reg(state, rs) >= read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (operand_parse.parse_immediate(rhs_operand)) |imm| {
            write_reg(state, rd, if (read_reg(state, rs) >= imm) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sgt")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // `sgt` register form is single-word `slt rd, rhs, rs`; immediate forms start with `$at` load.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                write_reg(state, rd, if (read_reg(state, rt) < read_reg(state, rs)) 1 else 0);
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (operand_parse.parse_register(rhs_operand)) |rt| {
            write_reg(state, rd, if (read_reg(state, rs) > read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (operand_parse.parse_immediate(rhs_operand)) |imm| {
            write_reg(state, rd, if (read_reg(state, rs) > imm) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sle")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // `sle` first expansion word is `slt rd, rhs, rs`.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                write_reg(state, rd, if (read_reg(state, rt) < read_reg(state, rs)) 1 else 0);
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (operand_parse.parse_register(rhs_operand)) |rt| {
            write_reg(state, rd, if (read_reg(state, rs) <= read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (operand_parse.parse_immediate(rhs_operand)) |imm| {
            write_reg(state, rd, if (read_reg(state, rs) <= imm) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sgeu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // `sgeu` first expansion word is `sltu rd, rs, rhs`.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                const rhs: u32 = @bitCast(read_reg(state, rt));
                write_reg(state, rd, if (lhs < rhs) 1 else 0);
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (operand_parse.parse_register(rhs_operand)) |rt| {
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, if (lhs >= rhs) 1 else 0);
            return .ok;
        }
        if (operand_parse.parse_immediate(rhs_operand)) |imm| {
            const rhs: u32 = @bitCast(imm);
            write_reg(state, rd, if (lhs >= rhs) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sgtu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // `sgtu` register form is single-word `sltu rd, rhs, rs`; immediate forms start with `$at` load.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                const rhs: u32 = @bitCast(read_reg(state, rt));
                write_reg(state, rd, if (rhs < lhs) 1 else 0);
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (operand_parse.parse_register(rhs_operand)) |rt| {
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, if (lhs > rhs) 1 else 0);
            return .ok;
        }
        if (operand_parse.parse_immediate(rhs_operand)) |imm| {
            const rhs: u32 = @bitCast(imm);
            write_reg(state, rd, if (lhs > rhs) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "sleu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs_operand = instruction_operand(instruction, 2);
        if (delay_slot_active(state)) {
            // `sleu` first expansion word is `sltu rd, rhs, rs`.
            if (operand_parse.parse_register(rhs_operand)) |rt| {
                const rhs: u32 = @bitCast(read_reg(state, rt));
                write_reg(state, rd, if (rhs < lhs) 1 else 0);
                return .ok;
            }
            if (operand_parse.parse_immediate(rhs_operand)) |imm| {
                delay_slot_first_word_set_at_from_immediate(state, imm);
                return .ok;
            }
            return .parse_error;
        }
        if (operand_parse.parse_register(rhs_operand)) |rt| {
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, if (lhs <= rhs) 1 else 0);
            return .ok;
        }
        if (operand_parse.parse_immediate(rhs_operand)) |imm| {
            const rhs: u32 = @bitCast(imm);
            write_reg(state, rd, if (lhs <= rhs) 1 else 0);
            return .ok;
        }
        return .parse_error;
    }

    if (std.mem.eql(u8, op, "movn")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rt) != 0) {
            write_reg(state, rd, read_reg(state, rs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movz")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rt) == 0) {
            write_reg(state, rd, read_reg(state, rs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movf")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (!get_fp_condition_flag(state, cc)) {
            write_reg(state, rd, read_reg(state, rs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movt")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (get_fp_condition_flag(state, cc)) {
            write_reg(state, rd, read_reg(state, rs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "lui")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm16 = operand_parse.parse_imm16_bits(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_reg(state, rt, @bitCast(imm16 << 16));
        return .ok;
    }

    // Floating-point arithmetic and compare group.
    if (std.mem.eql(u8, op, "add.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f32 = @bitCast(read_fp_single(state, fs));
        const rhs: f32 = @bitCast(read_fp_single(state, ft));
        write_fp_single(state, fd, @bitCast(lhs + rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sub.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f32 = @bitCast(read_fp_single(state, fs));
        const rhs: f32 = @bitCast(read_fp_single(state, ft));
        write_fp_single(state, fd, @bitCast(lhs - rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mul.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f32 = @bitCast(read_fp_single(state, fs));
        const rhs: f32 = @bitCast(read_fp_single(state, ft));
        write_fp_single(state, fd, @bitCast(lhs * rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "div.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: f32 = @bitCast(read_fp_single(state, fs));
        const rhs: f32 = @bitCast(read_fp_single(state, ft));
        write_fp_single(state, fd, @bitCast(lhs / rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sqrt.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(read_fp_single(state, fs));
        const result: f32 = if (value < 0.0) std.math.nan(f32) else @floatCast(@sqrt(@as(f64, value)));
        write_fp_single(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "add.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(read_fp_double(state, fs));
        const rhs: f64 = @bitCast(read_fp_double(state, ft));
        write_fp_double(state, fd, @bitCast(lhs + rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sub.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(read_fp_double(state, fs));
        const rhs: f64 = @bitCast(read_fp_double(state, ft));
        write_fp_double(state, fd, @bitCast(lhs - rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mul.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(read_fp_double(state, fs));
        const rhs: f64 = @bitCast(read_fp_double(state, ft));
        write_fp_double(state, fd, @bitCast(lhs * rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "div.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(read_fp_double(state, fs));
        const rhs: f64 = @bitCast(read_fp_double(state, ft));
        write_fp_double(state, fd, @bitCast(lhs / rhs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "sqrt.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(read_fp_double(state, fs));
        const result: f64 = if (value < 0.0) std.math.nan(f64) else @sqrt(value);
        write_fp_double(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "floor.w.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(read_fp_single(state, fs));
        var floor_value = fp_math.round_word_default_single(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f32, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f32, @floatFromInt(std.math.maxInt(i32))))
        {
            floor_value = @intFromFloat(@floor(value));
        }
        write_fp_single(state, fd, @bitCast(floor_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ceil.w.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(read_fp_single(state, fs));
        var ceil_value = fp_math.round_word_default_single(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f32, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f32, @floatFromInt(std.math.maxInt(i32))))
        {
            ceil_value = @intFromFloat(@ceil(value));
        }
        write_fp_single(state, fd, @bitCast(ceil_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "round.w.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(read_fp_single(state, fs));
        write_fp_single(state, fd, @bitCast(fp_math.round_to_nearest_even_single(value)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "trunc.w.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(read_fp_single(state, fs));
        var trunc_value = fp_math.round_word_default_single(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f32, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f32, @floatFromInt(std.math.maxInt(i32))))
        {
            trunc_value = @intFromFloat(@trunc(value));
        }
        write_fp_single(state, fd, @bitCast(trunc_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "floor.w.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(read_fp_double(state, fs));
        var floor_value = fp_math.round_word_default_double(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f64, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f64, @floatFromInt(std.math.maxInt(i32))))
        {
            floor_value = @intFromFloat(@floor(value));
        }
        write_fp_single(state, fd, @bitCast(floor_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "ceil.w.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(read_fp_double(state, fs));
        var ceil_value = fp_math.round_word_default_double(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f64, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f64, @floatFromInt(std.math.maxInt(i32))))
        {
            ceil_value = @intFromFloat(@ceil(value));
        }
        write_fp_single(state, fd, @bitCast(ceil_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "round.w.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(read_fp_double(state, fs));
        write_fp_single(state, fd, @bitCast(fp_math.round_to_nearest_even_double(value)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "trunc.w.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(read_fp_double(state, fs));
        var trunc_value = fp_math.round_word_default_double(value);
        if (!std.math.isNan(value) and !std.math.isInf(value) and
            value >= @as(f64, @floatFromInt(std.math.minInt(i32))) and
            value <= @as(f64, @floatFromInt(std.math.maxInt(i32))))
        {
            trunc_value = @intFromFloat(@trunc(value));
        }
        write_fp_single(state, fd, @bitCast(trunc_value));
        return .ok;
    }

    if (std.mem.eql(u8, op, "abs.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const bits = read_fp_single(state, fs) & 0x7FFF_FFFF;
        write_fp_single(state, fd, bits);
        return .ok;
    }

    if (std.mem.eql(u8, op, "abs.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        write_fp_single(state, fd + 1, read_fp_single(state, fs + 1) & 0x7FFF_FFFF);
        write_fp_single(state, fd, read_fp_single(state, fs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.d.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        const value: f32 = @bitCast(read_fp_single(state, fs));
        const result: f64 = value;
        write_fp_double(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.d.w")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        const value: i32 = @bitCast(read_fp_single(state, fs));
        const result: f64 = @floatFromInt(value);
        write_fp_double(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.s.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(read_fp_double(state, fs));
        const result: f32 = @floatCast(value);
        write_fp_single(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.s.w")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: i32 = @bitCast(read_fp_single(state, fs));
        const result: f32 = @floatFromInt(value);
        write_fp_single(state, fd, @bitCast(result));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.w.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        const value: f64 = @bitCast(read_fp_double(state, fs));
        write_fp_single(state, fd, @bitCast(fp_math.java_double_to_i32_cast(value)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "cvt.w.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const value: f32 = @bitCast(read_fp_single(state, fs));
        write_fp_single(state, fd, @bitCast(fp_math.java_float_to_i32_cast(value)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mov.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_fp_single(state, fd, read_fp_single(state, fs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mov.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        write_fp_single(state, fd, read_fp_single(state, fs));
        write_fp_single(state, fd + 1, read_fp_single(state, fs + 1));
        return .ok;
    }

    if (std.mem.eql(u8, op, "movf.s")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (!get_fp_condition_flag(state, cc)) {
            write_fp_single(state, fd, read_fp_single(state, fs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movf.d")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (!get_fp_condition_flag(state, cc)) {
            write_fp_single(state, fd, read_fp_single(state, fs));
            write_fp_single(state, fd + 1, read_fp_single(state, fs + 1));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movt.s")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (get_fp_condition_flag(state, cc)) {
            write_fp_single(state, fd, read_fp_single(state, fs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movt.d")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 2)) orelse return .parse_error
        else
            0;
        if (get_fp_condition_flag(state, cc)) {
            write_fp_single(state, fd, read_fp_single(state, fs));
            write_fp_single(state, fd + 1, read_fp_single(state, fs + 1));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movn.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rt) != 0) {
            write_fp_single(state, fd, read_fp_single(state, fs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movn.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (read_reg(state, rt) != 0) {
            write_fp_single(state, fd, read_fp_single(state, fs));
            write_fp_single(state, fd + 1, read_fp_single(state, fs + 1));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movz.s")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rt) == 0) {
            write_fp_single(state, fd, read_fp_single(state, fs));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "movz.d")) {
        if (instruction.operand_count != 3) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 2)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (read_reg(state, rt) == 0) {
            write_fp_single(state, fd, read_fp_single(state, fs));
            write_fp_single(state, fd + 1, read_fp_single(state, fs + 1));
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "mfc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_reg(state, rt, @bitCast(read_fp_single(state, fs)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mfc1.d")) {
        // Double transfer pseudo-op into register pair (rt, rt+1).
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (rt >= 31) return .runtime_error;
        if (delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word: `mfc1 rt, fs`.
            write_reg(state, rt, @bitCast(read_fp_single(state, fs)));
            return .ok;
        }
        write_reg(state, rt, @bitCast(read_fp_single(state, fs)));
        write_reg(state, rt + 1, @bitCast(read_fp_single(state, fs + 1)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mtc1")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_fp_single(state, fs, @bitCast(read_reg(state, rt)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "mtc1.d")) {
        // Double transfer pseudo-op from register pair (rt, rt+1).
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (rt >= 31) return .runtime_error;
        if (delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word: `mtc1 rt, fs`.
            write_fp_single(state, fs, @bitCast(read_reg(state, rt)));
            return .ok;
        }
        write_fp_single(state, fs, @bitCast(read_reg(state, rt)));
        write_fp_single(state, fs + 1, @bitCast(read_reg(state, rt + 1)));
        return .ok;
    }

    if (std.mem.eql(u8, op, "neg.s")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_fp_single(state, fd, read_fp_single(state, fs) ^ 0x8000_0000);
        return .ok;
    }

    if (std.mem.eql(u8, op, "neg.d")) {
        if (instruction.operand_count != 2) return .parse_error;
        const fd = operand_parse.parse_fp_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fd)) return .runtime_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        write_fp_single(state, fd + 1, read_fp_single(state, fs + 1) ^ 0x8000_0000);
        write_fp_single(state, fd, read_fp_single(state, fs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.eq.s")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        const lhs: f32 = @bitCast(read_fp_single(state, fs));
        const rhs: f32 = @bitCast(read_fp_single(state, ft));
        set_fp_condition_flag(state, cc, lhs == rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.le.s")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        const lhs: f32 = @bitCast(read_fp_single(state, fs));
        const rhs: f32 = @bitCast(read_fp_single(state, ft));
        set_fp_condition_flag(state, cc, lhs <= rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.lt.s")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        const lhs: f32 = @bitCast(read_fp_single(state, fs));
        const rhs: f32 = @bitCast(read_fp_single(state, ft));
        set_fp_condition_flag(state, cc, lhs < rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.eq.d")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(read_fp_double(state, fs));
        const rhs: f64 = @bitCast(read_fp_double(state, ft));
        set_fp_condition_flag(state, cc, lhs == rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.le.d")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(read_fp_double(state, fs));
        const rhs: f64 = @bitCast(read_fp_double(state, ft));
        set_fp_condition_flag(state, cc, lhs <= rhs);
        return .ok;
    }

    if (std.mem.eql(u8, op, "c.lt.d")) {
        if (instruction.operand_count != 2 and instruction.operand_count != 3) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 3)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const fs_operand_index: u8 = if (instruction.operand_count == 3) 1 else 0;
        const ft_operand_index: u8 = if (instruction.operand_count == 3) 2 else 1;
        const fs = operand_parse.parse_fp_register(instruction_operand(instruction, fs_operand_index)) orelse return .parse_error;
        const ft = operand_parse.parse_fp_register(instruction_operand(instruction, ft_operand_index)) orelse return .parse_error;
        if (!fp_double_register_pair_valid(fs)) return .runtime_error;
        if (!fp_double_register_pair_valid(ft)) return .runtime_error;
        const lhs: f64 = @bitCast(read_fp_double(state, fs));
        const rhs: f64 = @bitCast(read_fp_double(state, ft));
        set_fp_condition_flag(state, cc, lhs < rhs);
        return .ok;
    }

    // Control-flow group.
    if (std.mem.eql(u8, op, "j")) {
        if (instruction.operand_count != 1) return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 0)) orelse return .parse_error;
        process_jump_instruction(state, target);
        return .ok;
    }

    if (std.mem.eql(u8, op, "b")) {
        // Pseudo-op alias for unconditional branch.
        if (instruction.operand_count != 1) return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 0)) orelse return .parse_error;
        process_branch_instruction(state, target);
        return .ok;
    }

    if (std.mem.eql(u8, op, "bc1t")) {
        if (instruction.operand_count != 1 and instruction.operand_count != 2) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 2)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const target_operand_index: u8 = if (instruction.operand_count == 2) 1 else 0;
        const target = find_label(parsed, instruction_operand(instruction, target_operand_index)) orelse return .parse_error;
        if (get_fp_condition_flag(state, cc)) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bc1f")) {
        if (instruction.operand_count != 1 and instruction.operand_count != 2) return .parse_error;
        const cc: u3 = if (instruction.operand_count == 2)
            operand_parse.parse_condition_flag(instruction_operand(instruction, 0)) orelse return .parse_error
        else
            0;
        const target_operand_index: u8 = if (instruction.operand_count == 2) 1 else 0;
        const target = find_label(parsed, instruction_operand(instruction, target_operand_index)) orelse return .parse_error;
        if (!get_fp_condition_flag(state, cc)) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "blt")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rs) < read_reg(state, rt)) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bge")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rs) >= read_reg(state, rt)) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgt")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rs) > read_reg(state, rt)) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "ble")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rs) <= read_reg(state, rt)) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bltu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        if (lhs < rhs) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgeu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        if (lhs >= rhs) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgtu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        if (lhs > rhs) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bleu")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        if (lhs <= rhs) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "beq")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rs) == read_reg(state, rt)) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bne")) {
        if (instruction.operand_count != 3) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 2)) orelse return .parse_error;
        if (read_reg(state, rs) != read_reg(state, rt)) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "beqz")) {
        // Pseudo-op alias for `beq $rs, $zero, label`.
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) == 0) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bnez")) {
        // Pseudo-op alias for `bne $rs, $zero, label`.
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) != 0) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgez")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) >= 0) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgezal")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) >= 0) {
            process_return_address(parsed, state, 31);
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bgtz")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) > 0) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "blez")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) <= 0) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bltz")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) < 0) {
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "bltzal")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) < 0) {
            process_return_address(parsed, state, 31);
            process_branch_instruction(state, target);
        }
        return .ok;
    }

    if (std.mem.eql(u8, op, "jal")) {
        if (instruction.operand_count != 1) return .parse_error;
        const target = find_label(parsed, instruction_operand(instruction, 0)) orelse return .parse_error;
        process_return_address(parsed, state, 31);
        process_jump_instruction(state, target);
        return .ok;
    }

    if (std.mem.eql(u8, op, "jr")) {
        if (instruction.operand_count != 1) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const target_addr: u32 = @bitCast(read_reg(state, rs));
        const target_index = text_address_to_instruction_index(parsed, target_addr) orelse return .runtime_error;
        process_jump_instruction(state, target_index);
        return .ok;
    }

    if (std.mem.eql(u8, op, "jalr")) {
        if (instruction.operand_count != 1 and instruction.operand_count != 2) return .parse_error;
        const rd: u5 = if (instruction.operand_count == 2)
            operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error
        else
            31;
        const rs_operand_index: u8 = if (instruction.operand_count == 2) 1 else 0;
        const rs = operand_parse.parse_register(instruction_operand(instruction, rs_operand_index)) orelse return .parse_error;
        const target_addr: u32 = @bitCast(read_reg(state, rs));
        const target_index = text_address_to_instruction_index(parsed, target_addr) orelse return .runtime_error;
        process_return_address(parsed, state, rd);
        process_jump_instruction(state, target_index);
        return .ok;
    }

    if (std.mem.eql(u8, op, "break")) {
        if (instruction.operand_count > 1) return .parse_error;
        return .runtime_error;
    }

    if (std.mem.eql(u8, op, "teq")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) == read_reg(state, rt)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "teqi")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = operand_parse.parse_signed_imm16(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) == imm) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tne")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) != read_reg(state, rt)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tnei")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = operand_parse.parse_signed_imm16(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) != imm) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tge")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) >= read_reg(state, rt)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tgeu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        if (lhs >= rhs) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tgei")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = operand_parse.parse_signed_imm16(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) >= imm) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tgeiu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = operand_parse.parse_signed_imm16(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(imm);
        if (lhs >= rhs) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tlt")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) < read_reg(state, rt)) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tltu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(read_reg(state, rt));
        if (lhs < rhs) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tlti")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = operand_parse.parse_signed_imm16(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (read_reg(state, rs) < imm) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "tltiu")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const imm = operand_parse.parse_signed_imm16(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(imm);
        if (lhs < rhs) return .runtime_error;
        return .ok;
    }

    if (std.mem.eql(u8, op, "mfc0")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_reg(state, rt, state.cp0_regs[rd]);
        return .ok;
    }

    if (std.mem.eql(u8, op, "mtc0")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rt = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        state.cp0_regs[rd] = read_reg(state, rt);
        return .ok;
    }

    if (std.mem.eql(u8, op, "eret")) {
        if (instruction.operand_count != 0) return .parse_error;
        // STATUS bit 1 is EXL in MARS.
        const status_bits: u32 = @bitCast(state.cp0_regs[12]);
        state.cp0_regs[12] = @bitCast(status_bits & ~@as(u32, 1 << 1));
        const epc_address: u32 = @bitCast(state.cp0_regs[14]);
        const target_index = text_address_to_instruction_index(parsed, epc_address) orelse return .runtime_error;
        state.pc = target_index;
        return .ok;
    }

    // Small arithmetic pseudo-instruction helpers.
    if (std.mem.eql(u8, op, "neg")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_reg(state, rd, -%read_reg(state, rs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "abs")) {
        // Integer absolute value pseudo-op.
        if (instruction.operand_count != 2) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        if (delay_slot_active(state)) {
            // Delay-slot behavior executes only first expanded word: `sra $at, rs, 31`.
            write_reg(state, 1, read_reg(state, rs) >> 31);
            return .ok;
        }
        const value = read_reg(state, rs);
        write_reg(state, rd, if (value < 0) -%value else value);
        return .ok;
    }

    if (std.mem.eql(u8, op, "negu")) {
        // Unsigned negate pseudo-op alias (`subu $rd, $zero, $rs`).
        if (instruction.operand_count != 2) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        write_reg(state, rd, 0 -% read_reg(state, rs));
        return .ok;
    }

    if (std.mem.eql(u8, op, "not")) {
        if (instruction.operand_count != 2) return .parse_error;
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
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

    return .parse_error;
}

fn execute_patched_instruction(
    parsed: *Program,
    state: *ExecState,
    current_instruction_index: u32,
    word: u32,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    // Patched text words are raw machine encodings written via `sw` into text memory.
    const opcode = word >> 26;
    const current_word_index = parsed.instruction_word_indices[current_instruction_index];
    if (opcode == 0) {
        if (word == 0) return .ok;
        const rs: u5 = @intCast((word >> 21) & 0x1F);
        const rt: u5 = @intCast((word >> 16) & 0x1F);
        const rd: u5 = @intCast((word >> 11) & 0x1F);
        const shamt: u5 = @intCast((word >> 6) & 0x1F);
        const funct = word & 0x3F;

        if (funct == 0x20) {
            // add
            const lhs = read_reg(state, rs);
            const rhs = read_reg(state, rt);
            const sum = lhs +% rhs;
            if (signed_add_overflow(lhs, rhs, sum)) return .runtime_error;
            write_reg(state, rd, sum);
            return .ok;
        }
        if (funct == 0x0C) {
            return execute_syscall(parsed, state, output, output_len_bytes);
        }
        if (funct == 0x21) {
            // addu
            write_reg(state, rd, read_reg(state, rs) +% read_reg(state, rt));
            return .ok;
        }
        if (funct == 0x22) {
            // sub
            const lhs = read_reg(state, rs);
            const rhs = read_reg(state, rt);
            const dif = lhs -% rhs;
            if (signed_sub_overflow(lhs, rhs, dif)) return .runtime_error;
            write_reg(state, rd, dif);
            return .ok;
        }
        if (funct == 0x23) {
            // subu
            write_reg(state, rd, read_reg(state, rs) -% read_reg(state, rt));
            return .ok;
        }
        if (funct == 0x24) {
            // and
            const lhs: u32 = @bitCast(read_reg(state, rs));
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(lhs & rhs));
            return .ok;
        }
        if (funct == 0x25) {
            // or
            const lhs: u32 = @bitCast(read_reg(state, rs));
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(lhs | rhs));
            return .ok;
        }
        if (funct == 0x26) {
            // xor
            const lhs: u32 = @bitCast(read_reg(state, rs));
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(lhs ^ rhs));
            return .ok;
        }
        if (funct == 0x27) {
            // nor
            const lhs: u32 = @bitCast(read_reg(state, rs));
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(~(lhs | rhs)));
            return .ok;
        }
        if (funct == 0x00) {
            // sll
            const value: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(value << shamt));
            return .ok;
        }
        if (funct == 0x02) {
            // srl
            const value: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(value >> shamt));
            return .ok;
        }
        if (funct == 0x03) {
            // sra
            const value = read_reg(state, rt);
            write_reg(state, rd, value >> shamt);
            return .ok;
        }
        if (funct == 0x04) {
            // sllv
            const shift: u5 = @intCast(@as(u32, @bitCast(read_reg(state, rs))) & 0x1F);
            const value: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(value << shift));
            return .ok;
        }
        if (funct == 0x06) {
            // srlv
            const shift: u5 = @intCast(@as(u32, @bitCast(read_reg(state, rs))) & 0x1F);
            const value: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(value >> shift));
            return .ok;
        }
        if (funct == 0x07) {
            // srav
            const shift: u5 = @intCast(@as(u32, @bitCast(read_reg(state, rs))) & 0x1F);
            write_reg(state, rd, read_reg(state, rt) >> shift);
            return .ok;
        }
        if (funct == 0x01) {
            // movf / movt
            if ((rt & 0b10) != 0) return .runtime_error;
            const cc: u3 = @intCast((rt >> 2) & 0x7);
            const move_if_true = (rt & 1) == 1;
            const condition = get_fp_condition_flag(state, cc);
            const should_move = if (move_if_true) condition else !condition;
            if (should_move) {
                write_reg(state, rd, read_reg(state, rs));
            }
            return .ok;
        }
        if (funct == 0x0A) {
            // movz
            if (read_reg(state, rt) == 0) {
                write_reg(state, rd, read_reg(state, rs));
            }
            return .ok;
        }
        if (funct == 0x0B) {
            // movn
            if (read_reg(state, rt) != 0) {
                write_reg(state, rd, read_reg(state, rs));
            }
            return .ok;
        }
        if (funct == 0x08) {
            // jr
            const target_address: u32 = @bitCast(read_reg(state, rs));
            const target_index = text_address_to_instruction_index(parsed, target_address) orelse return .runtime_error;
            process_jump_instruction(state, target_index);
            return .ok;
        }
        if (funct == 0x09) {
            // jalr
            const return_address = patched_return_address(state, current_word_index);
            write_reg(state, rd, @bitCast(return_address));
            const target_address: u32 = @bitCast(read_reg(state, rs));
            const target_index = text_address_to_instruction_index(parsed, target_address) orelse return .runtime_error;
            process_jump_instruction(state, target_index);
            return .ok;
        }
        if (funct == 0x0D) {
            // break
            return .runtime_error;
        }
        if (funct == 0x10) {
            // mfhi
            write_reg(state, rd, state.hi);
            return .ok;
        }
        if (funct == 0x11) {
            // mthi
            state.hi = read_reg(state, rs);
            return .ok;
        }
        if (funct == 0x12) {
            // mflo
            write_reg(state, rd, state.lo);
            return .ok;
        }
        if (funct == 0x13) {
            // mtlo
            state.lo = read_reg(state, rs);
            return .ok;
        }
        if (funct == 0x18) {
            // mult
            const lhs: i64 = read_reg(state, rs);
            const rhs: i64 = read_reg(state, rt);
            const product: i64 = lhs * rhs;
            state.lo = @intCast(product & 0xFFFF_FFFF);
            state.hi = @intCast((product >> 32) & 0xFFFF_FFFF);
            return .ok;
        }
        if (funct == 0x19) {
            // multu
            const lhs: u64 = @intCast(@as(u32, @bitCast(read_reg(state, rs))));
            const rhs: u64 = @intCast(@as(u32, @bitCast(read_reg(state, rt))));
            const product: u64 = lhs * rhs;
            state.lo = @bitCast(@as(u32, @intCast(product & 0xFFFF_FFFF)));
            state.hi = @bitCast(@as(u32, @intCast((product >> 32) & 0xFFFF_FFFF)));
            return .ok;
        }
        if (funct == 0x1A) {
            // div
            const divisor = read_reg(state, rt);
            if (divisor == 0) return .ok;
            const dividend = read_reg(state, rs);
            state.lo = @divTrunc(dividend, divisor);
            state.hi = @rem(dividend, divisor);
            return .ok;
        }
        if (funct == 0x1B) {
            // divu
            const divisor: u32 = @bitCast(read_reg(state, rt));
            if (divisor == 0) return .ok;
            const dividend: u32 = @bitCast(read_reg(state, rs));
            state.lo = @bitCast(dividend / divisor);
            state.hi = @bitCast(dividend % divisor);
            return .ok;
        }
        if (funct == 0x2A) {
            // slt
            write_reg(state, rd, if (read_reg(state, rs) < read_reg(state, rt)) 1 else 0);
            return .ok;
        }
        if (funct == 0x2B) {
            // sltu
            const lhs: u32 = @bitCast(read_reg(state, rs));
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, if (lhs < rhs) 1 else 0);
            return .ok;
        }
        if (funct == 0x30) {
            // tge
            if (read_reg(state, rs) >= read_reg(state, rt)) return .runtime_error;
            return .ok;
        }
        if (funct == 0x31) {
            // tgeu
            const lhs: u32 = @bitCast(read_reg(state, rs));
            const rhs: u32 = @bitCast(read_reg(state, rt));
            if (lhs >= rhs) return .runtime_error;
            return .ok;
        }
        if (funct == 0x32) {
            // tlt
            if (read_reg(state, rs) < read_reg(state, rt)) return .runtime_error;
            return .ok;
        }
        if (funct == 0x33) {
            // tltu
            const lhs: u32 = @bitCast(read_reg(state, rs));
            const rhs: u32 = @bitCast(read_reg(state, rt));
            if (lhs < rhs) return .runtime_error;
            return .ok;
        }
        if (funct == 0x34) {
            // teq
            if (read_reg(state, rs) == read_reg(state, rt)) return .runtime_error;
            return .ok;
        }
        if (funct == 0x36) {
            // tne
            if (read_reg(state, rs) != read_reg(state, rt)) return .runtime_error;
            return .ok;
        }
        return .runtime_error;
    }

    if (opcode == 0x1C) {
        // SPECIAL2 encodings used by MARS for clz/clo/mul.
        const rs: u5 = @intCast((word >> 21) & 0x1F);
        const rt: u5 = @intCast((word >> 16) & 0x1F);
        const rd: u5 = @intCast((word >> 11) & 0x1F);
        const funct = word & 0x3F;

        if (funct == 0x00) {
            // madd
            const product: i64 = @as(i64, read_reg(state, rs)) * @as(i64, read_reg(state, rt));
            const hi_bits: u32 = @bitCast(state.hi);
            const lo_bits: u32 = @bitCast(state.lo);
            const hilo_bits: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
            const hilo_signed: i64 = @bitCast(hilo_bits);
            const sum = hilo_signed +% product;
            const sum_bits: u64 = @bitCast(sum);
            state.hi = @bitCast(@as(u32, @intCast((sum_bits >> 32) & 0xFFFF_FFFF)));
            state.lo = @bitCast(@as(u32, @intCast(sum_bits & 0xFFFF_FFFF)));
            return .ok;
        }
        if (funct == 0x01) {
            // maddu
            const product: u64 = @as(u64, @intCast(@as(u32, @bitCast(read_reg(state, rs))))) *
                @as(u64, @intCast(@as(u32, @bitCast(read_reg(state, rt)))));
            const hi_bits: u32 = @bitCast(state.hi);
            const lo_bits: u32 = @bitCast(state.lo);
            const hilo: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
            const sum = hilo +% product;
            state.hi = @bitCast(@as(u32, @intCast((sum >> 32) & 0xFFFF_FFFF)));
            state.lo = @bitCast(@as(u32, @intCast(sum & 0xFFFF_FFFF)));
            return .ok;
        }
        if (funct == 0x02) {
            // mul
            const product: i64 = @as(i64, read_reg(state, rs)) * @as(i64, read_reg(state, rt));
            state.hi = @intCast((product >> 32) & 0xFFFF_FFFF);
            state.lo = @intCast(product & 0xFFFF_FFFF);
            write_reg(state, rd, state.lo);
            return .ok;
        }
        if (funct == 0x04) {
            // msub
            const product: i64 = @as(i64, read_reg(state, rs)) * @as(i64, read_reg(state, rt));
            const hi_bits: u32 = @bitCast(state.hi);
            const lo_bits: u32 = @bitCast(state.lo);
            const hilo_bits: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
            const hilo_signed: i64 = @bitCast(hilo_bits);
            const sum = hilo_signed -% product;
            const sum_bits: u64 = @bitCast(sum);
            state.hi = @bitCast(@as(u32, @intCast((sum_bits >> 32) & 0xFFFF_FFFF)));
            state.lo = @bitCast(@as(u32, @intCast(sum_bits & 0xFFFF_FFFF)));
            return .ok;
        }
        if (funct == 0x05) {
            // msubu
            const product: u64 = @as(u64, @intCast(@as(u32, @bitCast(read_reg(state, rs))))) *
                @as(u64, @intCast(@as(u32, @bitCast(read_reg(state, rt)))));
            const hi_bits: u32 = @bitCast(state.hi);
            const lo_bits: u32 = @bitCast(state.lo);
            const hilo: u64 = (@as(u64, hi_bits) << 32) | @as(u64, lo_bits);
            const sum = hilo -% product;
            state.hi = @bitCast(@as(u32, @intCast((sum >> 32) & 0xFFFF_FFFF)));
            state.lo = @bitCast(@as(u32, @intCast(sum & 0xFFFF_FFFF)));
            return .ok;
        }
        if (funct == 0x20) {
            // clz
            const value: u32 = @bitCast(read_reg(state, rs));
            write_reg(state, rd, @intCast(@clz(value)));
            return .ok;
        }
        if (funct == 0x21) {
            // clo
            const value: u32 = @bitCast(read_reg(state, rs));
            write_reg(state, rd, @intCast(@clz(~value)));
            return .ok;
        }
        return .runtime_error;
    }

    const rs: u5 = @intCast((word >> 21) & 0x1F);
    const rt: u5 = @intCast((word >> 16) & 0x1F);
    const imm_bits: u16 = @truncate(word);
    const imm_signed: i16 = @bitCast(imm_bits);
    const imm_signed_i32: i32 = imm_signed;
    const imm_unsigned_u32: u32 = imm_bits;

    if (opcode == 0x08) {
        // addi
        const lhs = read_reg(state, rs);
        const rhs = imm_signed_i32;
        const sum = lhs +% rhs;
        if (signed_add_overflow(lhs, rhs, sum)) return .runtime_error;
        write_reg(state, rt, sum);
        return .ok;
    }

    if (opcode == 0x09) {
        // addiu
        write_reg(state, rt, read_reg(state, rs) +% imm_signed_i32);
        return .ok;
    }

    if (opcode == 0x0A) {
        // slti
        write_reg(state, rt, if (read_reg(state, rs) < imm_signed_i32) 1 else 0);
        return .ok;
    }

    if (opcode == 0x0B) {
        // sltiu
        const lhs: u32 = @bitCast(read_reg(state, rs));
        const rhs: u32 = @bitCast(imm_signed_i32);
        write_reg(state, rt, if (lhs < rhs) 1 else 0);
        return .ok;
    }

    if (opcode == 0x0C) {
        // andi
        const lhs: u32 = @bitCast(read_reg(state, rs));
        write_reg(state, rt, @bitCast(lhs & imm_unsigned_u32));
        return .ok;
    }

    if (opcode == 0x0D) {
        // ori
        const lhs: u32 = @bitCast(read_reg(state, rs));
        write_reg(state, rt, @bitCast(lhs | imm_unsigned_u32));
        return .ok;
    }

    if (opcode == 0x0E) {
        // xori
        const lhs: u32 = @bitCast(read_reg(state, rs));
        write_reg(state, rt, @bitCast(lhs ^ imm_unsigned_u32));
        return .ok;
    }

    if (opcode == 0x0F) {
        // lui
        write_reg(state, rt, @bitCast(imm_unsigned_u32 << 16));
        return .ok;
    }

    if (opcode == 0x23) {
        // lw
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 3) != 0) return .runtime_error;
        const value = read_u32_be(parsed, address) orelse return .runtime_error;
        write_reg(state, rt, @bitCast(value));
        return .ok;
    }

    if (opcode == 0x31) {
        // lwc1
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 3) != 0) return .runtime_error;
        const value = read_u32_be(parsed, address) orelse return .runtime_error;
        write_fp_single(state, rt, value);
        return .ok;
    }

    if (opcode == 0x35) {
        // ldc1
        if (!fp_double_register_pair_valid(rt)) return .runtime_error;
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 7) != 0) return .runtime_error;
        const value_low = read_u32_be(parsed, address) orelse return .runtime_error;
        const value_high = read_u32_be(parsed, address + 4) orelse return .runtime_error;
        write_fp_single(state, rt, value_low);
        write_fp_single(state, rt + 1, value_high);
        return .ok;
    }

    if (opcode == 0x20) {
        // lb
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        const value_u8 = read_u8(parsed, address) orelse return .runtime_error;
        const value_i8: i8 = @bitCast(value_u8);
        write_reg(state, rt, value_i8);
        return .ok;
    }

    if (opcode == 0x24) {
        // lbu
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        const value_u8 = read_u8(parsed, address) orelse return .runtime_error;
        write_reg(state, rt, value_u8);
        return .ok;
    }

    if (opcode == 0x21) {
        // lh
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 1) != 0) return .runtime_error;
        const value_u16 = read_u16_be(parsed, address) orelse return .runtime_error;
        const value_i16: i16 = @bitCast(value_u16);
        write_reg(state, rt, value_i16);
        return .ok;
    }

    if (opcode == 0x25) {
        // lhu
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 1) != 0) return .runtime_error;
        const value_u16 = read_u16_be(parsed, address) orelse return .runtime_error;
        write_reg(state, rt, value_u16);
        return .ok;
    }

    if (opcode == 0x22) {
        // lwl
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        var result: u32 = @bitCast(read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= mod_u2) : (i += 1) {
            const source_byte = read_u8(parsed, address - i) orelse return .runtime_error;
            const byte_index: u2 = @intCast(3 - i);
            result = fp_math.int_set_byte(result, byte_index, source_byte);
        }
        write_reg(state, rt, @bitCast(result));
        return .ok;
    }

    if (opcode == 0x26) {
        // lwr
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        var result: u32 = @bitCast(read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= @as(u2, 3 - mod_u2)) : (i += 1) {
            const source_byte = read_u8(parsed, address + i) orelse return .runtime_error;
            result = fp_math.int_set_byte(result, i, source_byte);
        }
        write_reg(state, rt, @bitCast(result));
        return .ok;
    }

    if (opcode == 0x30) {
        // ll
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 3) != 0) return .runtime_error;
        const value = read_u32_be(parsed, address) orelse return .runtime_error;
        write_reg(state, rt, @bitCast(value));
        return .ok;
    }

    if (opcode == 0x2B) {
        // sw
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 3) != 0) return .runtime_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u32(parsed, state, address, value)) return .runtime_error;
        return .ok;
    }

    if (opcode == 0x39) {
        // swc1
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 3) != 0) return .runtime_error;
        if (!write_u32(parsed, state, address, read_fp_single(state, rt))) return .runtime_error;
        return .ok;
    }

    if (opcode == 0x3D) {
        // sdc1
        if (!fp_double_register_pair_valid(rt)) return .runtime_error;
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 7) != 0) return .runtime_error;
        if (!write_u32(parsed, state, address, read_fp_single(state, rt))) return .runtime_error;
        if (!write_u32(parsed, state, address + 4, read_fp_single(state, rt + 1))) return .runtime_error;
        return .ok;
    }

    if (opcode == 0x28) {
        // sb
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u8(parsed, address, @intCast(value & 0xFF))) return .runtime_error;
        return .ok;
    }

    if (opcode == 0x29) {
        // sh
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 1) != 0) return .runtime_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u16_be(parsed, address, @intCast(value & 0xFFFF))) return .runtime_error;
        return .ok;
    }

    if (opcode == 0x2A) {
        // swl
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        const source: u32 = @bitCast(read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= mod_u2) : (i += 1) {
            const byte_index: u2 = @intCast(3 - i);
            if (!write_u8(parsed, address - i, fp_math.int_get_byte(source, byte_index))) return .runtime_error;
        }
        return .ok;
    }

    if (opcode == 0x2E) {
        // swr
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        const source: u32 = @bitCast(read_reg(state, rt));
        const mod_u2: u2 = @intCast(address & 3);
        var i: u2 = 0;
        while (i <= @as(u2, 3 - mod_u2)) : (i += 1) {
            if (!write_u8(parsed, address + i, fp_math.int_get_byte(source, i))) return .runtime_error;
        }
        return .ok;
    }

    if (opcode == 0x38) {
        // sc
        const base_address: u32 = @bitCast(read_reg(state, rs));
        const address = base_address +% @as(u32, @bitCast(imm_signed_i32));
        if ((address & 3) != 0) return .runtime_error;
        const value: u32 = @bitCast(read_reg(state, rt));
        if (!write_u32(parsed, state, address, value)) return .runtime_error;
        write_reg(state, rt, 1);
        return .ok;
    }

    if (opcode == 0x04 or opcode == 0x05) {
        // beq / bne
        const lhs = read_reg(state, rs);
        const rhs = read_reg(state, rt);
        const taken = if (opcode == 0x04) lhs == rhs else lhs != rhs;
        if (!taken) return .ok;

        const target_index = patched_branch_target_instruction_index(
            parsed,
            current_word_index,
            imm_signed_i32,
        ) orelse return .runtime_error;
        process_branch_instruction(state, target_index);
        return .ok;
    }

    if (opcode == 0x06 or opcode == 0x07) {
        // blez / bgtz
        const lhs = read_reg(state, rs);
        const taken = if (opcode == 0x06) lhs <= 0 else lhs > 0;
        if (!taken) return .ok;
        const target_index = patched_branch_target_instruction_index(
            parsed,
            current_word_index,
            imm_signed_i32,
        ) orelse return .runtime_error;
        process_branch_instruction(state, target_index);
        return .ok;
    }

    if (opcode == 0x01) {
        // REGIMM branch/trap family.
        var taken = false;
        var link_register = false;
        const lhs = read_reg(state, rs);
        if (rt == 0x08) {
            // tgei
            if (lhs >= imm_signed_i32) return .runtime_error;
            return .ok;
        } else if (rt == 0x09) {
            // tgeiu
            const lhs_u32: u32 = @bitCast(lhs);
            const rhs_u32: u32 = @bitCast(imm_signed_i32);
            if (lhs_u32 >= rhs_u32) return .runtime_error;
            return .ok;
        } else if (rt == 0x0A) {
            // tlti
            if (lhs < imm_signed_i32) return .runtime_error;
            return .ok;
        } else if (rt == 0x0B) {
            // tltiu
            const lhs_u32: u32 = @bitCast(lhs);
            const rhs_u32: u32 = @bitCast(imm_signed_i32);
            if (lhs_u32 < rhs_u32) return .runtime_error;
            return .ok;
        } else if (rt == 0x0C) {
            // teqi
            if (lhs == imm_signed_i32) return .runtime_error;
            return .ok;
        } else if (rt == 0x0E) {
            // tnei
            if (lhs != imm_signed_i32) return .runtime_error;
            return .ok;
        } else if (rt == 0x00) {
            taken = lhs < 0;
        } else if (rt == 0x01) {
            taken = lhs >= 0;
        } else if (rt == 0x10) {
            taken = lhs < 0;
            link_register = true;
        } else if (rt == 0x11) {
            taken = lhs >= 0;
            link_register = true;
        } else {
            return .runtime_error;
        }

        if (!taken) return .ok;
        if (link_register) {
            const return_address = patched_return_address(state, current_word_index);
            write_reg(state, 31, @bitCast(return_address));
        }
        const target_index = patched_branch_target_instruction_index(
            parsed,
            current_word_index,
            imm_signed_i32,
        ) orelse return .runtime_error;
        process_branch_instruction(state, target_index);
        return .ok;
    }

    if (opcode == 0x10) {
        // Coprocessor 0 transfer and eret.
        const cop0_rs = (word >> 21) & 0x1F;
        const cop0_rt: u5 = @intCast((word >> 16) & 0x1F);
        const cop0_rd: u5 = @intCast((word >> 11) & 0x1F);
        if (cop0_rs == 0x00) {
            // mfc0
            write_reg(state, cop0_rt, state.cp0_regs[cop0_rd]);
            return .ok;
        }
        if (cop0_rs == 0x04) {
            // mtc0
            state.cp0_regs[cop0_rd] = read_reg(state, cop0_rt);
            return .ok;
        }
        if (cop0_rs == 0x10 and (word & 0x3F) == 0x18) {
            // eret
            const status_bits: u32 = @bitCast(state.cp0_regs[12]);
            state.cp0_regs[12] = @bitCast(status_bits & ~@as(u32, 1 << 1));
            const epc_address: u32 = @bitCast(state.cp0_regs[14]);
            const target_index = text_address_to_instruction_index(parsed, epc_address) orelse return .runtime_error;
            state.pc = target_index;
            return .ok;
        }
        return .runtime_error;
    }

    if (opcode == 0x11) {
        // Coprocessor 1 transfer/branch/arithmetic decode.
        const cop1_rs = (word >> 21) & 0x1F;
        const cop1_rt: u5 = @intCast((word >> 16) & 0x1F);
        const cop1_fs: u5 = @intCast((word >> 11) & 0x1F);
        const cop1_fd: u5 = @intCast((word >> 6) & 0x1F);
        const cop1_funct = word & 0x3F;

        if (cop1_rs == 0x00) {
            // mfc1
            write_reg(state, cop1_rt, @bitCast(read_fp_single(state, cop1_fs)));
            return .ok;
        }
        if (cop1_rs == 0x04) {
            // mtc1
            write_fp_single(state, cop1_fs, @bitCast(read_reg(state, cop1_rt)));
            return .ok;
        }
        if (cop1_rs == 0x08) {
            // bc1f / bc1t (non-likely forms only).
            if ((cop1_rt & 0b10) != 0) return .runtime_error;
            const cc: u3 = @intCast((cop1_rt >> 2) & 0x7);
            const branch_on_true = (cop1_rt & 1) == 1;
            const condition = get_fp_condition_flag(state, cc);
            const taken = if (branch_on_true) condition else !condition;
            if (!taken) return .ok;
            const target_index = patched_branch_target_instruction_index(
                parsed,
                current_word_index,
                imm_signed_i32,
            ) orelse return .runtime_error;
            process_branch_instruction(state, target_index);
            return .ok;
        }

        if (cop1_rs == 0x10) {
            // fmt.s operations
            const ft = cop1_rt;
            const fs = cop1_fs;
            const fd = cop1_fd;

            if (cop1_funct == 0x11) {
                // movf.s / movt.s
                if ((ft & 0b10) != 0) return .runtime_error;
                const cc: u3 = @intCast((ft >> 2) & 0x7);
                const move_if_true = (ft & 1) == 1;
                const condition = get_fp_condition_flag(state, cc);
                const should_move = if (move_if_true) condition else !condition;
                if (should_move) {
                    write_fp_single(state, fd, read_fp_single(state, fs));
                }
                return .ok;
            }
            if (cop1_funct == 0x12) {
                // movz.s
                if (read_reg(state, ft) == 0) {
                    write_fp_single(state, fd, read_fp_single(state, fs));
                }
                return .ok;
            }
            if (cop1_funct == 0x13) {
                // movn.s
                if (read_reg(state, ft) != 0) {
                    write_fp_single(state, fd, read_fp_single(state, fs));
                }
                return .ok;
            }

            if (cop1_funct == 0x00) {
                const lhs: f32 = @bitCast(read_fp_single(state, fs));
                const rhs: f32 = @bitCast(read_fp_single(state, ft));
                write_fp_single(state, fd, @bitCast(lhs + rhs));
                return .ok;
            }
            if (cop1_funct == 0x01) {
                const lhs: f32 = @bitCast(read_fp_single(state, fs));
                const rhs: f32 = @bitCast(read_fp_single(state, ft));
                write_fp_single(state, fd, @bitCast(lhs - rhs));
                return .ok;
            }
            if (cop1_funct == 0x02) {
                const lhs: f32 = @bitCast(read_fp_single(state, fs));
                const rhs: f32 = @bitCast(read_fp_single(state, ft));
                write_fp_single(state, fd, @bitCast(lhs * rhs));
                return .ok;
            }
            if (cop1_funct == 0x03) {
                const lhs: f32 = @bitCast(read_fp_single(state, fs));
                const rhs: f32 = @bitCast(read_fp_single(state, ft));
                write_fp_single(state, fd, @bitCast(lhs / rhs));
                return .ok;
            }
            if (cop1_funct == 0x04) {
                const value: f32 = @bitCast(read_fp_single(state, fs));
                const result: f32 = if (value < 0.0) std.math.nan(f32) else @floatCast(@sqrt(@as(f64, value)));
                write_fp_single(state, fd, @bitCast(result));
                return .ok;
            }
            if (cop1_funct == 0x05) {
                write_fp_single(state, fd, read_fp_single(state, fs) & 0x7FFF_FFFF);
                return .ok;
            }
            if (cop1_funct == 0x06 or cop1_funct == 0x20) {
                // mov.s / cvt.s.s
                write_fp_single(state, fd, read_fp_single(state, fs));
                return .ok;
            }
            if (cop1_funct == 0x07) {
                write_fp_single(state, fd, read_fp_single(state, fs) ^ 0x8000_0000);
                return .ok;
            }
            if (cop1_funct == 0x21) {
                // cvt.d.s
                if (!fp_double_register_pair_valid(fd)) return .runtime_error;
                const value: f32 = @bitCast(read_fp_single(state, fs));
                const result: f64 = @floatCast(value);
                write_fp_double(state, fd, @bitCast(result));
                return .ok;
            }
            if (cop1_funct == 0x24) {
                // cvt.w.s
                const value: f32 = @bitCast(read_fp_single(state, fs));
                write_fp_single(state, fd, @bitCast(fp_math.round_word_default_single(value)));
                return .ok;
            }
            if (cop1_funct == 0x0C) {
                // round.w.s
                const value: f32 = @bitCast(read_fp_single(state, fs));
                write_fp_single(state, fd, @bitCast(fp_math.round_to_nearest_even_single(value)));
                return .ok;
            }
            if (cop1_funct == 0x0D) {
                // trunc.w.s
                const value: f32 = @bitCast(read_fp_single(state, fs));
                var trunc_value = fp_math.round_word_default_single(value);
                if (!std.math.isNan(value) and !std.math.isInf(value) and
                    value >= @as(f32, @floatFromInt(std.math.minInt(i32))) and
                    value <= @as(f32, @floatFromInt(std.math.maxInt(i32))))
                {
                    trunc_value = @intFromFloat(@trunc(value));
                }
                write_fp_single(state, fd, @bitCast(trunc_value));
                return .ok;
            }
            if (cop1_funct == 0x0E) {
                // ceil.w.s
                const value: f32 = @bitCast(read_fp_single(state, fs));
                var ceil_value = fp_math.round_word_default_single(value);
                if (!std.math.isNan(value) and !std.math.isInf(value) and
                    value >= @as(f32, @floatFromInt(std.math.minInt(i32))) and
                    value <= @as(f32, @floatFromInt(std.math.maxInt(i32))))
                {
                    ceil_value = @intFromFloat(@ceil(value));
                }
                write_fp_single(state, fd, @bitCast(ceil_value));
                return .ok;
            }
            if (cop1_funct == 0x0F) {
                // floor.w.s
                const value: f32 = @bitCast(read_fp_single(state, fs));
                var floor_value = fp_math.round_word_default_single(value);
                if (!std.math.isNan(value) and !std.math.isInf(value) and
                    value >= @as(f32, @floatFromInt(std.math.minInt(i32))) and
                    value <= @as(f32, @floatFromInt(std.math.maxInt(i32))))
                {
                    floor_value = @intFromFloat(@floor(value));
                }
                write_fp_single(state, fd, @bitCast(floor_value));
                return .ok;
            }
            if (cop1_funct == 0x32 or cop1_funct == 0x3C or cop1_funct == 0x3E) {
                // c.eq.s / c.lt.s / c.le.s
                const cc: u3 = @intCast((word >> 8) & 0x7);
                const lhs: f32 = @bitCast(read_fp_single(state, fs));
                const rhs: f32 = @bitCast(read_fp_single(state, ft));
                if (cop1_funct == 0x32) {
                    set_fp_condition_flag(state, cc, lhs == rhs);
                } else if (cop1_funct == 0x3C) {
                    set_fp_condition_flag(state, cc, lhs < rhs);
                } else {
                    set_fp_condition_flag(state, cc, lhs <= rhs);
                }
                return .ok;
            }
            return .runtime_error;
        }

        if (cop1_rs == 0x11) {
            // fmt.d operations
            const ft = cop1_rt;
            const fs = cop1_fs;
            const fd = cop1_fd;
            if (!fp_double_register_pair_valid(fs)) return .runtime_error;

            if (cop1_funct == 0x11) {
                // movf.d / movt.d
                if (!fp_double_register_pair_valid(fd)) return .runtime_error;
                if ((ft & 0b10) != 0) return .runtime_error;
                const cc: u3 = @intCast((ft >> 2) & 0x7);
                const move_if_true = (ft & 1) == 1;
                const condition = get_fp_condition_flag(state, cc);
                const should_move = if (move_if_true) condition else !condition;
                if (should_move) {
                    write_fp_single(state, fd, read_fp_single(state, fs));
                    write_fp_single(state, fd + 1, read_fp_single(state, fs + 1));
                }
                return .ok;
            }
            if (cop1_funct == 0x12) {
                // movz.d
                if (!fp_double_register_pair_valid(fd)) return .runtime_error;
                if (read_reg(state, ft) == 0) {
                    write_fp_single(state, fd, read_fp_single(state, fs));
                    write_fp_single(state, fd + 1, read_fp_single(state, fs + 1));
                }
                return .ok;
            }
            if (cop1_funct == 0x13) {
                // movn.d
                if (!fp_double_register_pair_valid(fd)) return .runtime_error;
                if (read_reg(state, ft) != 0) {
                    write_fp_single(state, fd, read_fp_single(state, fs));
                    write_fp_single(state, fd + 1, read_fp_single(state, fs + 1));
                }
                return .ok;
            }

            if (cop1_funct == 0x00 or cop1_funct == 0x01 or cop1_funct == 0x02 or cop1_funct == 0x03) {
                if (!fp_double_register_pair_valid(fd)) return .runtime_error;
                if (!fp_double_register_pair_valid(ft)) return .runtime_error;
                const lhs: f64 = @bitCast(read_fp_double(state, fs));
                const rhs: f64 = @bitCast(read_fp_double(state, ft));
                if (cop1_funct == 0x00) {
                    write_fp_double(state, fd, @bitCast(lhs + rhs));
                } else if (cop1_funct == 0x01) {
                    write_fp_double(state, fd, @bitCast(lhs - rhs));
                } else if (cop1_funct == 0x02) {
                    write_fp_double(state, fd, @bitCast(lhs * rhs));
                } else {
                    write_fp_double(state, fd, @bitCast(lhs / rhs));
                }
                return .ok;
            }
            if (cop1_funct == 0x04) {
                if (!fp_double_register_pair_valid(fd)) return .runtime_error;
                const value: f64 = @bitCast(read_fp_double(state, fs));
                const result: f64 = if (value < 0.0) std.math.nan(f64) else @sqrt(value);
                write_fp_double(state, fd, @bitCast(result));
                return .ok;
            }
            if (cop1_funct == 0x05) {
                if (!fp_double_register_pair_valid(fd)) return .runtime_error;
                write_fp_single(state, fd + 1, read_fp_single(state, fs + 1) & 0x7FFF_FFFF);
                write_fp_single(state, fd, read_fp_single(state, fs));
                return .ok;
            }
            if (cop1_funct == 0x06 or cop1_funct == 0x21) {
                // mov.d / cvt.d.d
                if (!fp_double_register_pair_valid(fd)) return .runtime_error;
                write_fp_single(state, fd + 1, read_fp_single(state, fs + 1));
                write_fp_single(state, fd, read_fp_single(state, fs));
                return .ok;
            }
            if (cop1_funct == 0x07) {
                if (!fp_double_register_pair_valid(fd)) return .runtime_error;
                write_fp_single(state, fd + 1, read_fp_single(state, fs + 1) ^ 0x8000_0000);
                write_fp_single(state, fd, read_fp_single(state, fs));
                return .ok;
            }
            if (cop1_funct == 0x20) {
                // cvt.s.d
                const value: f64 = @bitCast(read_fp_double(state, fs));
                const result: f32 = @floatCast(value);
                write_fp_single(state, fd, @bitCast(result));
                return .ok;
            }
            if (cop1_funct == 0x24) {
                // cvt.w.d
                const value: f64 = @bitCast(read_fp_double(state, fs));
                write_fp_single(state, fd, @bitCast(fp_math.round_word_default_double(value)));
                return .ok;
            }
            if (cop1_funct == 0x0C) {
                // round.w.d
                const value: f64 = @bitCast(read_fp_double(state, fs));
                write_fp_single(state, fd, @bitCast(fp_math.round_to_nearest_even_double(value)));
                return .ok;
            }
            if (cop1_funct == 0x0D) {
                // trunc.w.d
                const value: f64 = @bitCast(read_fp_double(state, fs));
                var trunc_value = fp_math.round_word_default_double(value);
                if (!std.math.isNan(value) and !std.math.isInf(value) and
                    value >= @as(f64, @floatFromInt(std.math.minInt(i32))) and
                    value <= @as(f64, @floatFromInt(std.math.maxInt(i32))))
                {
                    trunc_value = @intFromFloat(@trunc(value));
                }
                write_fp_single(state, fd, @bitCast(trunc_value));
                return .ok;
            }
            if (cop1_funct == 0x0E) {
                // ceil.w.d
                const value: f64 = @bitCast(read_fp_double(state, fs));
                var ceil_value = fp_math.round_word_default_double(value);
                if (!std.math.isNan(value) and !std.math.isInf(value) and
                    value >= @as(f64, @floatFromInt(std.math.minInt(i32))) and
                    value <= @as(f64, @floatFromInt(std.math.maxInt(i32))))
                {
                    ceil_value = @intFromFloat(@ceil(value));
                }
                write_fp_single(state, fd, @bitCast(ceil_value));
                return .ok;
            }
            if (cop1_funct == 0x0F) {
                // floor.w.d
                const value: f64 = @bitCast(read_fp_double(state, fs));
                var floor_value = fp_math.round_word_default_double(value);
                if (!std.math.isNan(value) and !std.math.isInf(value) and
                    value >= @as(f64, @floatFromInt(std.math.minInt(i32))) and
                    value <= @as(f64, @floatFromInt(std.math.maxInt(i32))))
                {
                    floor_value = @intFromFloat(@floor(value));
                }
                write_fp_single(state, fd, @bitCast(floor_value));
                return .ok;
            }
            if (cop1_funct == 0x32 or cop1_funct == 0x3C or cop1_funct == 0x3E) {
                // c.eq.d / c.lt.d / c.le.d
                if (!fp_double_register_pair_valid(ft)) return .runtime_error;
                const cc: u3 = @intCast((word >> 8) & 0x7);
                const lhs: f64 = @bitCast(read_fp_double(state, fs));
                const rhs: f64 = @bitCast(read_fp_double(state, ft));
                if (cop1_funct == 0x32) {
                    set_fp_condition_flag(state, cc, lhs == rhs);
                } else if (cop1_funct == 0x3C) {
                    set_fp_condition_flag(state, cc, lhs < rhs);
                } else {
                    set_fp_condition_flag(state, cc, lhs <= rhs);
                }
                return .ok;
            }
            return .runtime_error;
        }

        if (cop1_rs == 0x14) {
            // fmt.w conversion source.
            const fs = cop1_fs;
            const fd = cop1_fd;
            const value: i32 = @bitCast(read_fp_single(state, fs));
            if (cop1_funct == 0x20) {
                // cvt.s.w
                const result: f32 = @floatFromInt(value);
                write_fp_single(state, fd, @bitCast(result));
                return .ok;
            }
            if (cop1_funct == 0x21) {
                // cvt.d.w
                if (!fp_double_register_pair_valid(fd)) return .runtime_error;
                const result: f64 = @floatFromInt(value);
                write_fp_double(state, fd, @bitCast(result));
                return .ok;
            }
            return .runtime_error;
        }
        return .runtime_error;
    }

    // Support encoded `j` so advanced SMC fixtures can redirect control flow.
    if (opcode == 2) {
        const target_index_field = word & 0x03FF_FFFF;
        const target_address = target_index_field << 2;
        const target_index = text_address_to_instruction_index(parsed, target_address) orelse return .runtime_error;
        process_jump_instruction(state, target_index);
        return .ok;
    }

    if (opcode == 3) {
        // jal
        const return_address = patched_return_address(state, current_word_index);
        write_reg(state, 31, @bitCast(return_address));
        const target_index_field = word & 0x03FF_FFFF;
        const target_address = target_index_field << 2;
        const target_index = text_address_to_instruction_index(parsed, target_address) orelse return .runtime_error;
        process_jump_instruction(state, target_index);
        return .ok;
    }

    return .runtime_error;
}

fn patched_return_address(state: *ExecState, current_word_index: u32) u32 {
    const delay_words: u32 = if (state.delayed_branching_enabled) 2 else 1;
    return text_base_addr + (current_word_index + delay_words) * 4;
}

fn patched_branch_target_instruction_index(
    parsed: *Program,
    current_word_index: u32,
    imm_signed_i32: i32,
) ?u32 {
    // MIPS I-type branches compute target from (PC + 4) + (offset << 2).
    const base: i64 = @as(i64, current_word_index) + 1;
    const target_word_signed = base + imm_signed_i32;
    if (target_word_signed < 0) return null;
    const target_word_index: u32 = @intCast(target_word_signed);
    const target_address = text_base_addr + target_word_index * 4;
    return text_address_to_instruction_index(parsed, target_address);
}

fn signed_add_overflow(lhs: i32, rhs: i32, sum: i32) bool {
    return (lhs >= 0 and rhs >= 0 and sum < 0) or (lhs < 0 and rhs < 0 and sum >= 0);
}

fn signed_sub_overflow(lhs: i32, rhs: i32, dif: i32) bool {
    return (lhs >= 0 and rhs < 0 and dif < 0) or (lhs < 0 and rhs >= 0 and dif >= 0);
}

fn process_branch_instruction(state: *ExecState, target_instruction_index: u32) void {
    // Branches and jumps share the same delay-slot registration path.
    if (state.delayed_branching_enabled) {
        delayed_branch_register(state, target_instruction_index);
    } else {
        state.pc = target_instruction_index;
    }
}

fn process_jump_instruction(state: *ExecState, target_instruction_index: u32) void {
    if (state.delayed_branching_enabled) {
        delayed_branch_register(state, target_instruction_index);
    } else {
        state.pc = target_instruction_index;
    }
}

fn delayed_branch_register(state: *ExecState, target_instruction_index: u32) void {
    switch (state.delayed_branch_state) {
        .cleared => {
            state.delayed_branch_target = target_instruction_index;
            state.delayed_branch_state = .registered;
        },
        .registered => {
            // Inner branch in the same delay chain is ignored by MARS semantics.
            state.delayed_branch_state = .registered;
        },
        .triggered => {
            // Branch in a delay slot replaces the pending target after trigger.
            state.delayed_branch_state = .registered;
        },
    }
}

fn execute_syscall(
    parsed: *Program,
    state: *ExecState,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    // Syscall service ID is carried in $v0, matching MARS/SPIM convention.
    const v0 = read_reg(state, 2);

    if (v0 == 1) {
        const value = read_reg(state, 4);
        return output_format.append_formatted(output, output_len_bytes, "{}", .{value});
    }

    if (v0 == 2) {
        const bits = read_fp_single(state, 12);
        const value: f32 = @bitCast(bits);
        return output_format.append_java_float(output, output_len_bytes, value);
    }

    if (v0 == 3) {
        const bits = read_fp_double(state, 12);
        const value: f64 = @bitCast(bits);
        return output_format.append_java_double(output, output_len_bytes, value);
    }

    if (v0 == 4) {
        const address: u32 = @bitCast(read_reg(state, 4));
        if (address < data_base_addr) return .runtime_error;
        const data_offset = address - data_base_addr;
        return append_c_string_from_data(parsed, data_offset, output, output_len_bytes);
    }

    if (v0 == 5) {
        if (input_exhausted_for_token(state)) return .needs_input;
        const value = read_next_input_int(state) orelse return .runtime_error;
        write_reg(state, 2, value);
        return .ok;
    }

    if (v0 == 6) {
        if (input_exhausted_for_token(state)) return .needs_input;
        const value = read_next_input_float(state) orelse return .runtime_error;
        write_fp_single(state, 0, @bitCast(value));
        return .ok;
    }

    if (v0 == 7) {
        if (input_exhausted_for_token(state)) return .needs_input;
        const value = read_next_input_double(state) orelse return .runtime_error;
        write_fp_double(state, 0, @bitCast(value));
        return .ok;
    }

    if (v0 == 8) {
        if (input_exhausted_at_eof(state)) return .needs_input;
        const buffer_address: u32 = @bitCast(read_reg(state, 4));
        const length = read_reg(state, 5);
        if (!syscall_read_string(parsed, state, buffer_address, length)) return .runtime_error;
        return .ok;
    }

    if (v0 == 9) {
        const allocation_size = read_reg(state, 4);
        const allocation_address = syscall_sbrk(state, allocation_size) orelse return .runtime_error;
        write_reg(state, 2, @bitCast(allocation_address));
        return .ok;
    }

    if (v0 == 10) {
        // Command-line MARS appends newline on exit service.
        const newline_status = output_format.append_bytes(output, output_len_bytes, "\n");
        if (newline_status != .ok) return newline_status;
        state.halted = true;
        return .ok;
    }

    if (v0 == 11) {
        const a0: u32 = @bitCast(read_reg(state, 4));
        const ch: u8 = @intCast(a0 & 0xFF);
        return output_format.append_bytes(output, output_len_bytes, &[_]u8{ch});
    }

    if (v0 == 12) {
        if (input_exhausted_at_eof(state)) return .needs_input;
        const ch = read_next_input_char(state) orelse return .runtime_error;
        write_reg(state, 2, ch);
        return .ok;
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
        // Close returns status only via errors; it does not overwrite $v0.
        if (!syscall_close_file(state)) return .runtime_error;
        return .ok;
    }

    if (v0 == 17) {
        // Exit2 uses $a0 as process exit code in MARS command mode.
        // MARS also emits a trailing newline to stdout when the run terminates.
        const newline_status = output_format.append_bytes(output, output_len_bytes, "\n");
        if (newline_status != .ok) return newline_status;
        state.halted = true;
        return .ok;
    }

    if (v0 == 30) {
        // Service 30 writes current wall-clock milliseconds split across $a0/$a1.
        const millis_bits = current_time_millis_bits();
        const low_word: u32 = @truncate(millis_bits);
        const high_word: u32 = @truncate(millis_bits >> 32);
        write_reg(state, 4, @bitCast(low_word));
        write_reg(state, 5, @bitCast(high_word));
        return .ok;
    }

    if (v0 == 31) {
        // MidiOut: command-mode behavior does not affect architectural state.
        // We still sanitize inputs so invalid ranges follow MARS fallback defaults.
        _ = sanitize_midi_parameter(read_reg(state, 4), 60);
        _ = sanitize_midi_duration(read_reg(state, 5), 1000);
        _ = sanitize_midi_parameter(read_reg(state, 6), 0);
        _ = sanitize_midi_parameter(read_reg(state, 7), 100);
        return .ok;
    }

    if (v0 == 32) {
        // Sleep is intentionally modeled as a no-op for deterministic wasm execution.
        _ = read_reg(state, 4);
        return .ok;
    }

    if (v0 == 33) {
        // MidiOutSync mirrors MidiOut state semantics in command-mode parity tests.
        _ = sanitize_midi_parameter(read_reg(state, 4), 60);
        _ = sanitize_midi_duration(read_reg(state, 5), 1000);
        _ = sanitize_midi_parameter(read_reg(state, 6), 0);
        _ = sanitize_midi_parameter(read_reg(state, 7), 100);
        return .ok;
    }

    if (v0 == 34) {
        const value: u32 = @bitCast(read_reg(state, 4));
        return output_format.append_formatted(output, output_len_bytes, "0x{x:0>8}", .{value});
    }

    if (v0 == 35) {
        const value: u32 = @bitCast(read_reg(state, 4));
        var temp: [32]u8 = undefined;
        var index: usize = 0;
        while (index < temp.len) : (index += 1) {
            const bit_index: u5 = @intCast(31 - index);
            temp[index] = if (((value >> bit_index) & 1) == 1) '1' else '0';
        }
        return output_format.append_bytes(output, output_len_bytes, temp[0..]);
    }

    if (v0 == 36) {
        const value: u32 = @bitCast(read_reg(state, 4));
        return output_format.append_formatted(output, output_len_bytes, "{}", .{value});
    }

    if (v0 == 40) {
        const stream_id = read_reg(state, 4);
        const seed = read_reg(state, 5);
        java_random.set_random_seed(state, stream_id, seed) orelse return .runtime_error;
        return .ok;
    }

    if (v0 == 41) {
        const stream_id = read_reg(state, 4);
        const random_value = java_random.next_int(state, stream_id) orelse return .runtime_error;
        write_reg(state, 4, random_value);
        return .ok;
    }

    if (v0 == 42) {
        const stream_id = read_reg(state, 4);
        const bound = read_reg(state, 5);
        const random_value = java_random.next_int_bound(state, stream_id, bound) orelse return .runtime_error;
        write_reg(state, 4, random_value);
        return .ok;
    }

    if (v0 == 43) {
        const stream_id = read_reg(state, 4);
        const random_value = java_random.next_float(state, stream_id) orelse return .runtime_error;
        write_fp_single(state, 0, @bitCast(random_value));
        return .ok;
    }

    if (v0 == 44) {
        const stream_id = read_reg(state, 4);
        const random_value = java_random.next_double(state, stream_id) orelse return .runtime_error;
        write_fp_double(state, 0, @bitCast(random_value));
        return .ok;
    }

    if (v0 == 50 or
        v0 == 51 or
        v0 == 52 or
        v0 == 53 or
        v0 == 54 or
        v0 == 55 or
        v0 == 56 or
        v0 == 57 or
        v0 == 58 or
        v0 == 59)
    {
        // Dialog services in headless command-mode MARS terminate with this message.
        return syscall_headless_dialog_termination(state, output, output_len_bytes);
    }

    if (v0 == 60) {
        // MARS extension: clear screen. Command-mode behavior is effectively no-op.
        return .ok;
    }

    return .runtime_error;
}

fn sanitize_midi_parameter(value: i32, default_value: i32) i32 {
    if (value < 0 or value > 127) return default_value;
    return value;
}

fn sanitize_midi_duration(value: i32, default_value: i32) i32 {
    if (value < 0) return default_value;
    return value;
}

fn current_time_millis_bits() u64 {
    if (builtin.target.cpu.arch == .wasm32) {
        // Freestanding wasm has no wall-clock API in this runtime.
        // A fixed non-zero value preserves testable architectural behavior.
        return 1;
    }
    const millis_i64 = std.time.milliTimestamp();
    return @bitCast(millis_i64);
}

fn syscall_headless_dialog_termination(
    state: *ExecState,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    // In this environment, MARS dialog syscalls throw HeadlessException and print:
    // "\nProgram terminated when maximum step limit -1 reached.\n\n"
    const status = output_format.append_bytes(
        output,
        output_len_bytes,
        "\nProgram terminated when maximum step limit -1 reached.\n\n",
    );
    if (status != .ok) return status;
    state.halted = true;
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
    // `la` in MARS can target either data labels or text labels.
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

const AddressExpression = union(enum) {
    empty,
    immediate: i32,
    label: []const u8,
    label_plus_offset: struct {
        label_name: []const u8,
        offset: i32,
    },
    invalid,
};

const AddressOperand = struct {
    base_register: ?u5,
    expression: AddressExpression,
};

fn parse_address_operand(operand_text: []const u8) ?AddressOperand {
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

fn parse_address_expression(expression_text: []const u8) AddressExpression {
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

    // MARS supports `label+imm` forms here but does not accept `label-imm`.
    if (std.mem.indexOfScalarPos(u8, trimmed, 1, '-') != null) return .invalid;

    return .{ .label = trimmed };
}

fn resolve_address_operand(parsed: *Program, state: *ExecState, operand_text: []const u8) ?u32 {
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

fn resolve_load_address(parsed: *Program, state: *ExecState, operand_text: []const u8) ?u32 {
    // Loads/stores accept immediate, label, and offset(base) forms.
    return resolve_address_operand(parsed, state, operand_text);
}

fn process_return_address(parsed: *Program, state: *ExecState, reg: u5) void {
    // Matches MARS processReturnAddress(): return is next instruction, or the one after delay slot.
    const target_instruction_index = if (state.delayed_branching_enabled)
        state.pc + 1
    else
        state.pc;
    const return_address = instruction_index_to_text_address(parsed, target_instruction_index) orelse text_base_addr;
    write_reg(state, reg, @bitCast(return_address));
}

fn text_address_to_instruction_index(parsed: *Program, address: u32) ?u32 {
    // Map machine text address back to source instruction via expansion table.
    if (address < text_base_addr) return null;
    const relative = address - text_base_addr;
    if ((relative & 3) != 0) return null;
    const word_index = relative / 4;
    if (word_index >= parsed.text_word_count) return null;
    if (!parsed.text_word_to_instruction_valid[word_index]) return null;
    return parsed.text_word_to_instruction_index[word_index];
}

fn instruction_index_to_text_address(parsed: *Program, instruction_index: u32) ?u32 {
    // Instruction index equal to instruction_count means "address past last word".
    if (instruction_index <= parsed.instruction_count) {
        const word_index = if (instruction_index < parsed.instruction_count)
            parsed.instruction_word_indices[instruction_index]
        else
            parsed.text_word_count;
        return text_base_addr + word_index * 4;
    }
    return null;
}

fn write_u32(parsed: *Program, state: *ExecState, address: u32, value: u32) bool {
    // Writes prefer data/heap memory and only patch text when SMC mode is enabled.
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
    // Service 4 prints bytes until a NUL terminator.
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
fn instruction_operand(instruction: *const LineInstruction, index: u8) []const u8 {
    assert(index < instruction.operand_count);
    return instruction.operands[index][0..instruction.operand_lens[index]];
}

fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

fn write_reg(state: *ExecState, reg: u5, value: i32) void {
    // Register zero is hard-wired to zero.
    if (reg == 0) return;
    state.regs[reg] = value;
}

fn read_fp_single(state: *ExecState, reg: u5) u32 {
    return state.fp_regs[reg];
}

fn write_fp_single(state: *ExecState, reg: u5, bits: u32) void {
    state.fp_regs[reg] = bits;
}

fn read_fp_double(state: *ExecState, reg: u5) u64 {
    const low_word = @as(u64, state.fp_regs[reg]);
    const high_word = @as(u64, state.fp_regs[reg + 1]);
    return (high_word << 32) | low_word;
}

fn write_fp_double(state: *ExecState, reg: u5, bits: u64) void {
    state.fp_regs[reg] = @intCast(bits & 0xFFFF_FFFF);
    state.fp_regs[reg + 1] = @intCast((bits >> 32) & 0xFFFF_FFFF);
}

fn fp_double_register_pair_valid(reg: u5) bool {
    if ((reg & 1) != 0) return false;
    return reg < 31;
}

fn set_fp_condition_flag(state: *ExecState, flag: u3, enabled: bool) void {
    const mask: u8 = @as(u8, 1) << flag;
    if (enabled) {
        state.fp_condition_flags |= mask;
    } else {
        state.fp_condition_flags &= ~mask;
    }
}

fn get_fp_condition_flag(state: *ExecState, flag: u3) bool {
    const mask: u8 = @as(u8, 1) << flag;
    return (state.fp_condition_flags & mask) != 0;
}

fn data_address_to_offset(parsed: *Program, address: u32) ?u32 {
    // Data segment is constrained to bytes initialized by directives.
    if (address < data_base_addr) return null;
    const offset = address - data_base_addr;
    if (offset >= parsed.data_len_bytes) return null;
    return offset;
}

fn heap_address_to_offset(address: u32) ?u32 {
    // Heap visibility is constrained to currently allocated sbrk extent.
    if (address < heap_base_addr) return null;
    const offset = address - heap_base_addr;
    if (offset >= exec_state_storage.heap_len_bytes) return null;
    return offset;
}

fn read_u8(parsed: *Program, address: u32) ?u8 {
    // Runtime memory model currently includes data and heap segments.
    if (data_address_to_offset(parsed, address)) |offset| {
        return parsed.data[offset];
    }
    if (heap_address_to_offset(address)) |offset| {
        return exec_state_storage.heap[offset];
    }
    return null;
}

fn read_u16_be(parsed: *Program, address: u32) ?u16 {
    const b0 = read_u8(parsed, address) orelse return null;
    const b1 = read_u8(parsed, address + 1) orelse return null;
    return @as(u16, b0) | (@as(u16, b1) << 8);
}

fn read_u32_be(parsed: *Program, address: u32) ?u32 {
    const b0 = read_u8(parsed, address) orelse return null;
    const b1 = read_u8(parsed, address + 1) orelse return null;
    const b2 = read_u8(parsed, address + 2) orelse return null;
    const b3 = read_u8(parsed, address + 3) orelse return null;
    return @as(u32, b0) |
        (@as(u32, b1) << 8) |
        (@as(u32, b2) << 16) |
        (@as(u32, b3) << 24);
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
    return @as(u64, b0) |
        (@as(u64, b1) << 8) |
        (@as(u64, b2) << 16) |
        (@as(u64, b3) << 24) |
        (@as(u64, b4) << 32) |
        (@as(u64, b5) << 40) |
        (@as(u64, b6) << 48) |
        (@as(u64, b7) << 56);
}

fn write_u8(parsed: *Program, address: u32, value: u8) bool {
    // Runtime memory model currently includes data and heap segments.
    if (data_address_to_offset(parsed, address)) |offset| {
        parsed.data[offset] = value;
        return true;
    }
    if (heap_address_to_offset(address)) |offset| {
        exec_state_storage.heap[offset] = value;
        return true;
    }
    return false;
}

fn write_u16_be(parsed: *Program, address: u32, value: u16) bool {
    return write_u8(parsed, address, @intCast(value & 0xFF)) and
        write_u8(parsed, address + 1, @intCast((value >> 8) & 0xFF));
}

fn write_u32_be(parsed: *Program, address: u32, value: u32) bool {
    return write_u8(parsed, address, @intCast(value & 0xFF)) and
        write_u8(parsed, address + 1, @intCast((value >> 8) & 0xFF)) and
        write_u8(parsed, address + 2, @intCast((value >> 16) & 0xFF)) and
        write_u8(parsed, address + 3, @intCast((value >> 24) & 0xFF));
}

/// Returns true when all remaining input (from current offset) is whitespace or empty.
/// Used by token-reading syscalls (5/6/7) to distinguish "no input available" from "parse error".
fn input_exhausted_for_token(state: *const ExecState) bool {
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    while (index < input_text.len and std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    return index >= input_text.len;
}

/// Returns true when input offset is at or past the end of available input.
/// Used by byte-level syscalls (8/12) that don't skip whitespace.
fn input_exhausted_at_eof(state: *const ExecState) bool {
    return state.input_offset_bytes >= state.input_text.len;
}

fn read_next_input_int(state: *ExecState) ?i32 {
    // Integer scanner intentionally consumes one numeric token and leaves trailing
    // whitespace/newline for later readers, matching service 5 expectations.
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

fn read_next_input_float(state: *ExecState) ?f32 {
    const token = read_next_input_token(state) orelse return null;
    return std.fmt.parseFloat(f32, token) catch null;
}

fn read_next_input_double(state: *ExecState) ?f64 {
    const token = read_next_input_token(state) orelse return null;
    return std.fmt.parseFloat(f64, token) catch null;
}

fn read_next_input_char(state: *ExecState) ?i32 {
    // Char reader consumes exactly one byte, including whitespace/newlines.
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    if (index >= input_text.len) return null;
    const byte = input_text[index];
    index += 1;
    state.input_offset_bytes = @intCast(index);
    return byte;
}

fn read_next_input_token(state: *ExecState) ?[]const u8 {
    // Float/double scanners reuse this token reader.
    const input_text = state.input_text;
    var index: usize = @intCast(state.input_offset_bytes);
    while (index < input_text.len and std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    if (index >= input_text.len) return null;

    const start = index;
    while (index < input_text.len and !std.ascii.isWhitespace(input_text[index])) : (index += 1) {}
    state.input_offset_bytes = @intCast(index);
    return input_text[start..index];
}

fn syscall_read_string(
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

    // Mirrors MARS fgets-like behavior: consume one line and add newline if room remains.
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
        if (!write_u8(parsed, dst_address, line[src_index])) return false;
    }

    if (string_length < max_length) {
        const newline_address = buffer_address + @as(u32, @intCast(string_length));
        if (!write_u8(parsed, newline_address, '\n')) return false;
        string_length += 1;
    }

    if (add_null_byte) {
        const null_address = buffer_address + @as(u32, @intCast(string_length));
        if (!write_u8(parsed, null_address, 0)) return false;
    }

    return true;
}

fn syscall_sbrk(state: *ExecState, allocation_size: i32) ?u32 {
    // MARS keeps heap word-aligned after each allocation.
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

fn syscall_open_file(parsed: *Program, state: *ExecState) i32 {
    // This runtime models files in-memory to keep wasm runs deterministic.
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

    // Copy from file contents into simulated memory.
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

    // Copy from simulated memory into file contents.
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

fn syscall_close_file(state: *ExecState) bool {
    const fd = read_reg(state, 4);
    const open_file = get_open_file(state, fd) orelse return false;
    open_file.in_use = false;
    open_file.file_index = 0;
    open_file.position_bytes = 0;
    open_file.flags = 0;
    return true;
}

const OpenFileMode = enum {
    truncate,
    append,
};

fn open_or_create_virtual_file(state: *ExecState, name: []const u8, mode: OpenFileMode) ?u32 {
    // Open with truncate can reuse an existing file entry.
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
    // File descriptor numbering starts at 3 to reserve stdin/stdout/stderr.
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
    // File names are read from runtime memory as NUL-terminated strings.
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

test "engine executes integer arithmetic fixture" {
    // Sanity check for arithmetic + jal/jr helper flow.
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

test "engine reports runtime error on addi overflow" {
    // Signed add-immediate must trap on overflow.
    const program =
        \\main:
        \\    li   $t0, 2147483647
        \\    addi $t1, $t0, 1
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine keeps hi lo unchanged on div by zero" {
    // MIPS leaves HI/LO unchanged when divisor is zero.
    const program =
        \\main:
        \\    li   $t0, 0x11111111
        \\    li   $t1, 0x22222222
        \\    mthi $t0
        \\    mtlo $t1
        \\    li   $t2, 123
        \\    li   $t3, 0
        \\    div  $t2, $t3
        \\    mfhi $a0
        \\    li   $v0, 34
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    mflo $a0
        \\    li   $v0, 34
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("0x11111111\n0x22222222\n", out[0..result.output_len_bytes]);
}

test "engine executes immediate logical instruction group" {
    // Covers zero/sign extension behavior across immediate instruction family.
    const program =
        \\main:
        \\    li   $t0, -1
        \\    andi $t1, $t0, 0xff00
        \\    ori  $t2, $zero, 0x1234
        \\    xori $t3, $t2, 0x00ff
        \\    li   $t4, -5
        \\    slti $t5, $t4, -4
        \\    sltiu $t6, $t4, -4
        \\    lui  $t7, 0x1234
        \\    li   $v0, 1
        \\    move $a0, $t1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t5
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t6
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t7
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("65280\n4811\n1\n1\n305397760\n", out[0..result.output_len_bytes]);
}

test "engine executes variable shifts" {
    // Covers variable shift mask behavior (`& 0x1F`) for all three variants.
    const program =
        \\main:
        \\    li   $t0, -16
        \\    li   $t1, 2
        \\    sllv $t2, $t0, $t1
        \\    srlv $t3, $t0, $t1
        \\    srav $t4, $t0, $t1
        \\    li   $v0, 1
        \\    move $a0, $t2
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t4
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("-64\n1073741820\n-4\n", out[0..result.output_len_bytes]);
}

test "engine supports syscall read string semantics" {
    // Service 8 should copy one line, append newline when room remains, and NUL-terminate.
    const program =
        \\.data
        \\buf: .space 32
        \\.text
        \\main:
        \\    li   $v0, 8
        \\    la   $a0, buf
        \\    li   $a1, 16
        \\    syscall
        \\    li   $v0, 4
        \\    la   $a0, buf
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "hello\n",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("hello\n\n", out[0..result.output_len_bytes]);
}

test "engine supports syscall read char and float double" {
    // Services 12/6/7 with print services validate token and byte-level input handling.
    const program =
        \\main:
        \\    li   $v0, 12
        \\    syscall
        \\    move $t0, $v0
        \\    li   $v0, 6
        \\    syscall
        \\    mov.s $f12, $f0
        \\    li   $v0, 2
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 7
        \\    syscall
        \\    mov.d $f12, $f0
        \\    li   $v0, 3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t0
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "Q 1.5 2.25",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("1.5\n2.25\n81\n", out[0..result.output_len_bytes]);
}

test "engine supports sbrk alignment and heap byte access" {
    // Service 9 should return previous break and round new break to word alignment.
    const program =
        \\main:
        \\    li   $a0, 1
        \\    li   $v0, 9
        \\    syscall
        \\    move $s0, $v0
        \\    li   $a0, 3
        \\    li   $v0, 9
        \\    syscall
        \\    move $s1, $v0
        \\    subu $t0, $s1, $s0
        \\    li   $v0, 1
        \\    move $a0, $t0
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $t1, 65
        \\    sb   $t1, 0($s0)
        \\    li   $t2, 66
        \\    sb   $t2, 0($s1)
        \\    li   $v0, 11
        \\    lb   $a0, 0($s0)
        \\    syscall
        \\    lb   $a0, 0($s1)
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("4\nAB\n", out[0..result.output_len_bytes]);
}

test "engine supports data directives ascii and align" {
    // `.ascii` length and `.align` padding should match text-visible addresses.
    const program =
        \\.data
        \\prefix: .ascii "AB"
        \\.align 2
        \\value_word: .word 0x11223344
        \\.text
        \\main:
        \\    la   $t0, prefix
        \\    la   $t1, value_word
        \\    subu $t2, $t1, $t0
        \\    li   $v0, 1
        \\    move $a0, $t2
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    lw   $a0, 0($t1)
        \\    li   $v0, 34
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("4\n0x11223344\n", out[0..result.output_len_bytes]);
}

test "engine close syscall leaves v0 unchanged" {
    // Service 16 parity check: `$v0` remains service id unless caller changes it.
    const program =
        \\main:
        \\    li   $v0, 16
        \\    li   $a0, 99
        \\    syscall
        \\    move $t0, $v0
        \\    li   $v0, 1
        \\    move $a0, $t0
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("16\n", out[0..result.output_len_bytes]);
}

test "engine executes partial-word memory instruction family" {
    const program =
        \\.data
        \\w: .word 0x11223344
        \\.text
        \\main:
        \\    la   $s0, w
        \\    ll   $t0, 0($s0)
        \\    sc   $t0, 0($s0)
        \\    move $t1, $t0
        \\    li   $t2, 0
        \\    lwl  $t2, 1($s0)
        \\    li   $t3, 0
        \\    lwr  $t3, 2($s0)
        \\    li   $v0, 34
        \\    move $a0, $t2
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 34
        \\    move $a0, $t3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t1
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("0x22110000\n0x00004433\n1\n", out[0..result.output_len_bytes]);
}

test "engine handles fp condition flag branch variants" {
    const program =
        \\.data
        \\one: .float 1.0
        \\two: .float 2.0
        \\.text
        \\main:
        \\    l.s   $f0, one
        \\    l.s   $f1, two
        \\    li    $s0, 0
        \\    c.lt.s 1, $f1, $f0
        \\    bc1f  1, flag_false
        \\    nop
        \\    li    $s0, 99
        \\flag_false:
        \\    addiu $s0, $s0, 7
        \\    li    $v0, 1
        \\    move  $a0, $s0
        \\    syscall
        \\    li    $v0, 10
        \\    syscall
    ;

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("7\n", out[0..result.output_len_bytes]);
}

test "engine supports cp0 transfer and eret flow" {
    const program =
        \\main:
        \\    li   $t0, 0x00000002
        \\    mtc0 $t0, $12
        \\    la   $t1, target
        \\    mtc0 $t1, $14
        \\    eret
        \\    li   $v0, 1
        \\    li   $a0, 999
        \\    syscall
        \\target:
        \\    mfc0 $t2, $12
        \\    li   $v0, 1
        \\    move $a0, $t2
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("0\n", out[0..result.output_len_bytes]);
}

test "engine raises runtime error on taken trap instruction" {
    const program =
        \\main:
        \\    li  $t0, 1
        \\    li  $t1, 1
        \\    teq $t0, $t1
        \\    li  $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine executes multiply accumulate and leading-bit operations" {
    const program =
        \\main:
        \\    li    $t0, 3
        \\    li    $t1, 4
        \\    mul   $t2, $t0, $t1
        \\    mflo  $s0
        \\    mthi  $zero
        \\    mtlo  $zero
        \\    li    $t3, -1
        \\    li    $t4, 2
        \\    maddu $t3, $t4
        \\    mfhi  $s1
        \\    mflo  $s2
        \\    clo   $s3, $t3
        \\    clz   $s4, $t4
        \\    li    $v0, 1
        \\    move  $a0, $s0
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    li    $v0, 34
        \\    move  $a0, $s1
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    li    $v0, 34
        \\    move  $a0, $s2
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    li    $v0, 1
        \\    move  $a0, $s3
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    li    $v0, 1
        \\    move  $a0, $s4
        \\    syscall
        \\    li    $v0, 10
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "12\n0x00000001\n0xfffffffe\n32\n30\n",
        out[0..result.output_len_bytes],
    );
}

test "engine supports syscall exit2 command-mode newline termination" {
    const program =
        \\main:
        \\    li   $a0, 60
        \\    li   $v0, 17
        \\    syscall
        \\    li   $v0, 1
        \\    li   $a0, 999
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("\n", out[0..result.output_len_bytes]);
}

test "engine supports syscall time service register updates" {
    const program =
        \\main:
        \\    li   $a0, 0
        \\    li   $a1, 0
        \\    li   $v0, 30
        \\    syscall
        \\    or   $t0, $a0, $a1
        \\    sltu $t1, $zero, $t0
        \\    li   $v0, 1
        \\    move $a0, $t1
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("1\n", out[0..result.output_len_bytes]);
}

test "engine supports midi and sleep syscalls without architectural side effects" {
    const program =
        \\main:
        \\    li   $a0, 60
        \\    li   $a1, 1
        \\    li   $a2, 0
        \\    li   $a3, 100
        \\    li   $v0, 31
        \\    syscall
        \\    li   $a0, 1
        \\    li   $v0, 32
        \\    syscall
        \\    li   $a0, 60
        \\    li   $a1, 1
        \\    li   $a2, 0
        \\    li   $a3, 100
        \\    li   $v0, 33
        \\    syscall
        \\    li   $v0, 1
        \\    li   $a0, 123
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("123\n", out[0..result.output_len_bytes]);
}

test "engine mirrors headless dialog syscall termination output" {
    const program =
        \\.data
        \\msg: .asciiz "headless dialog"
        \\.text
        \\main:
        \\    la   $a0, msg
        \\    li   $v0, 50
        \\    syscall
        \\    li   $v0, 1
        \\    li   $a0, 9
        \\    syscall
    ;

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "\nProgram terminated when maximum step limit -1 reached.\n\n",
        out[0..result.output_len_bytes],
    );
}

test "engine parser accepts set directive as no-op" {
    const program =
        \\.text
        \\.set noreorder
        \\main:
        \\    li   $v0, 1
        \\    li   $a0, 7
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("7\n", out[0..result.output_len_bytes]);
}

test "engine supports address expressions for la lw and sw" {
    const program =
        \\.data
        \\arr: .word 11, 22, 33, 44
        \\.text
        \\main:
        \\    lw   $t0, arr
        \\    lw   $t1, arr+4
        \\    li   $t8, 4
        \\    lw   $t2, arr($t8)
        \\    li   $v0, 1
        \\    move $a0, $t0
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $t2
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $s0, 77
        \\    sw   $s0, arr+8
        \\    lw   $s1, arr+8
        \\    li   $v0, 1
        \\    move $a0, $s1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    la   $s2, arr
        \\    la   $s3, arr+12
        \\    la   $s4, ($s2)
        \\    la   $s5, 4($s2)
        \\    la   $s6, arr($t8)
        \\    subu $s3, $s3, $s2
        \\    subu $s4, $s4, $s2
        \\    subu $s5, $s5, $s2
        \\    subu $s6, $s6, $s2
        \\    li   $v0, 1
        \\    move $a0, $s3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $s4
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $s5
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 1
        \\    move $a0, $s6
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    la   $t3, 65535($zero)
        \\    la   $t4, -1($zero)
        \\    la   $t5, 65536
        \\    li   $v0, 34
        \\    move $a0, $t3
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 34
        \\    move $a0, $t4
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 32
        \\    syscall
        \\    li   $v0, 34
        \\    move $a0, $t5
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [512]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "11 22 22\n77\n12 4 4 4\n0x0000ffff 0xffffffff 0x00010000\n",
        out[0..result.output_len_bytes],
    );
}

test "engine address operand estimators match MARS reference forms" {
    try std.testing.expectEqual(@as(u32, 2), estimate_la_word_count("arr"));
    try std.testing.expectEqual(@as(u32, 1), estimate_la_word_count("($t0)"));
    try std.testing.expectEqual(@as(u32, 2), estimate_la_word_count("0($t0)"));
    try std.testing.expectEqual(@as(u32, 3), estimate_la_word_count("-1($t0)"));
    try std.testing.expectEqual(@as(u32, 2), estimate_la_word_count("65535($t0)"));
    try std.testing.expectEqual(@as(u32, 3), estimate_la_word_count("65536($t0)"));

    try std.testing.expectEqual(@as(u32, 2), estimate_memory_operand_word_count("arr"));
    try std.testing.expectEqual(@as(u32, 3), estimate_memory_operand_word_count("arr($zero)"));
    try std.testing.expectEqual(@as(u32, 3), estimate_memory_operand_word_count("arr($t0)"));
    try std.testing.expectEqual(@as(u32, 1), estimate_memory_operand_word_count("32767($t0)"));
    try std.testing.expectEqual(@as(u32, 3), estimate_memory_operand_word_count("65535($t0)"));
    try std.testing.expectEqual(@as(u32, 1), estimate_memory_operand_word_count("32767"));
    try std.testing.expectEqual(@as(u32, 2), estimate_memory_operand_word_count("65535"));
}

test "engine rejects label minus offset address forms" {
    const program =
        \\.data
        \\arr: .word 1
        \\.text
        \\main:
        \\    lw   $t0, arr-4($zero)
        \\    li   $v0, 10
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.parse_error, result.status);
}

test "engine resolves end-of-text labels with pseudo-expanded counts" {
    const program =
        \\.text
        \\main:
        \\    la   $t0, tail
        \\    la   $t1, body
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
        \\body:
        \\    add  $s0, $s1, 100000
        \\tail:
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("12\n", out[0..result.output_len_bytes]);
}

test "engine estimates sne pseudo word counts from label deltas" {
    const program =
        \\.text
        \\main:
        \\    la   $t0, after_rr
        \\    la   $t1, before_rr
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    la   $t0, after_ri
        \\    la   $t1, before_ri
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    la   $t0, after_r32
        \\    la   $t1, before_r32
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
        \\before_rr:
        \\    sne  $s0, $s1, $s2
        \\after_rr:
        \\before_ri:
        \\    sne  $s0, $s1, 5
        \\after_ri:
        \\before_r32:
        \\    sne  $s0, $s1, 100000
        \\after_r32:
    ;

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("8\n12\n16\n", out[0..result.output_len_bytes]);
}

test "engine li with bit-31-set immediates expands to two words matching MARS" {
    // li with 32-bit hex values where bit 31 is set (negative as i32) must
    // expand to lui+ori (2 words), not addiu (which would miscount words and
    // shift all subsequent label addresses).
    const program =
        \\.text
        \\main:
        \\    la   $t0, after_zero_low
        \\    la   $t1, before_zero_low
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    la   $t0, after_nonzero_low
        \\    la   $t1, before_nonzero_low
        \\    subu $a0, $t0, $t1
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 34
        \\    move $a0, $t8
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    li   $v0, 34
        \\    move $a0, $t9
        \\    syscall
        \\    li   $v0, 10
        \\    syscall
        \\before_zero_low:
        \\    li   $t8, 0x82080000
        \\after_zero_low:
        \\before_nonzero_low:
        \\    li   $t9, 0x92090001
        \\after_nonzero_low:
    ;

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    // Each li should occupy 2 words = 8 bytes.
    // The loaded values must also be correct.
    try std.testing.expectEqualStrings("8\n8\n0x82080000\n0x92090001\n", out[0..result.output_len_bytes]);
}

test "engine executes patched integer and hilo decode families" {
    const program = @embedFile("../../test_programs/smc_patch_integer_hilo.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "19\n13\n1\n0\n196608\n2\n-1\n1\n48\n1\n-4\n30\n48\n",
        out[0..result.output_len_bytes],
    );
}

test "engine executes patched regimm and sign-branch decode families" {
    const program = @embedFile("../../test_programs/smc_patch_regimm_branches.s");

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("6\n4194504\n", out[0..result.output_len_bytes]);
}

test "engine executes patched partial-memory decode families" {
    const program = @embedFile("../../test_programs/smc_patch_partial_memory.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "68\n51\n13124\n13124\n1\n0x33441122\n0x33443333\n",
        out[0..result.output_len_bytes],
    );
}

test "engine executes patched trap and cp0 decode families" {
    const program = @embedFile("../../test_programs/smc_patch_trap_cp0.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("9\n9\n2\n0\n", out[0..result.output_len_bytes]);
}

test "engine executes patched cop1 transfer and branch decode families" {
    const program = @embedFile("../../test_programs/smc_patch_cop1_transfer_branch.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "1065353216\n1073741824\n0x3f800000\n",
        out[0..result.output_len_bytes],
    );
}

test "engine patched break triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $t8, 0x0000000D
        \\    la   $t9, slot_break
        \\    sw   $t8, 0($t9)
        \\    j    slot_break
        \\slot_break:
        \\    nop
        \\    li   $v0, 1
        \\    li   $a0, 999
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine patched teq true condition triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $s0, 7
        \\    li   $t8, 0x02100034
        \\    la   $t9, slot_teq
        \\    sw   $t8, 0($t9)
        \\    j    slot_teq
        \\slot_teq:
        \\    nop
        \\    li   $v0, 1
        \\    li   $a0, 999
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine patched teqi true condition triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $s0, 7
        \\    li   $t8, 0x060C0007
        \\    la   $t9, slot_teqi
        \\    sw   $t8, 0($t9)
        \\    j    slot_teqi
        \\slot_teqi:
        \\    nop
        \\    li   $v0, 1
        \\    li   $a0, 999
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine executes patched cop1 arithmetic and convert decode families" {
    const program = @embedFile("../../test_programs/smc_patch_cop1_arith_convert.s");

    var out: [512]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "1077936128\n1065353216\n1073741824\n1073741824\n2\n1\n2\n0x3f800000\n0xbf800000\n",
        out[0..result.output_len_bytes],
    );
}

test "engine executes patched special2 accumulation decode families" {
    const program = @embedFile("../../test_programs/smc_patch_special2_madd.s");

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("30\n60\n30\n0\n", out[0..result.output_len_bytes]);
}

test "engine executes fp missing ops coverage program" {
    const program = @embedFile("../../test_programs/fp_missing_ops.s");

    var out: [1024]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "2\n5\n4\n3\n3\n3\n3\n4\n3\n3\n4\n2\n0\n0x40400000\n0x40800000\n0x41100000\n4\n2\n",
        out[0..result.output_len_bytes],
    );
}

test "engine executes mulou coverage program including immediate form" {
    const program = @embedFile("../../test_programs/mulou_coverage.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("60000\n90000\n", out[0..result.output_len_bytes]);
}

test "engine source break instruction triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $a0, 77
        \\    jal  print_int_line
        \\    break
        \\    li   $a0, 88
        \\    jal  print_int_line
        \\    li   $v0, 10
        \\    syscall
        \\print_int_line:
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    jr   $ra
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
    try std.testing.expectEqualStrings("77\n", out[0..result.output_len_bytes]);
}

test "engine mulou immediate overflow triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li    $a0, 1
        \\    jal   print_int_line
        \\    li    $t0, 0x7fffffff
        \\    mulou $t1, $t0, 4
        \\    li    $a0, 2
        \\    jal   print_int_line
        \\    li    $v0, 10
        \\    syscall
        \\print_int_line:
        \\    li    $v0, 1
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    jr    $ra
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
    try std.testing.expectEqualStrings("1\n", out[0..result.output_len_bytes]);
}

test "engine executes pseudo div/rem forms coverage program" {
    const program = @embedFile("../../test_programs/pseudo_div_rem_forms.s");

    var out: [256]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("6\n2\n6\n2\n4\n0\n2\n6\n77\n88\n77\n88\n", out[0..result.output_len_bytes]);
}

test "engine pseudo div register zero divisor triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $a0, 99
        \\    jal  print_int_line
        \\    li   $s0, 20
        \\    li   $s1, 0
        \\    div  $t0, $s0, $s1
        \\    li   $a0, 42
        \\    jal  print_int_line
        \\print_int_line:
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    jr   $ra
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
    try std.testing.expectEqualStrings("99\n", out[0..result.output_len_bytes]);
}

test "engine pseudo divu register zero divisor triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $a0, 99
        \\    jal  print_int_line
        \\    li   $s0, 20
        \\    li   $s1, 0
        \\    divu $t0, $s0, $s1
        \\    li   $a0, 42
        \\    jal  print_int_line
        \\print_int_line:
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    jr   $ra
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
    try std.testing.expectEqualStrings("99\n", out[0..result.output_len_bytes]);
}

test "engine pseudo rem register zero divisor triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $a0, 99
        \\    jal  print_int_line
        \\    li   $s0, 20
        \\    li   $s1, 0
        \\    rem  $t0, $s0, $s1
        \\    li   $a0, 42
        \\    jal  print_int_line
        \\print_int_line:
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    jr   $ra
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
    try std.testing.expectEqualStrings("99\n", out[0..result.output_len_bytes]);
}

test "engine pseudo remu register zero divisor triggers runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $a0, 99
        \\    jal  print_int_line
        \\    li   $s0, 20
        \\    li   $s1, 0
        \\    remu $t0, $s0, $s1
        \\    li   $a0, 42
        \\    jal  print_int_line
        \\print_int_line:
        \\    li   $v0, 1
        \\    syscall
        \\    li   $v0, 11
        \\    li   $a0, 10
        \\    syscall
        \\    jr   $ra
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
    try std.testing.expectEqualStrings("99\n", out[0..result.output_len_bytes]);
}

test "engine delayed-slot multiword li executes first expansion word only" {
    const program = @embedFile("../../test_programs/delay_slot_pseudo_li_db.s");

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("7\n\n", out[0..result.output_len_bytes]);
}

test "engine delayed-slot multiword mulu executes first expansion word only" {
    const program = @embedFile("../../test_programs/delay_slot_pseudo_mulu_db.s");

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("123\n\n", out[0..result.output_len_bytes]);
}

test "engine delayed-slot compare and abs pseudo forms execute first expansion word only" {
    const program = @embedFile("../../test_programs/delay_slot_pseudo_compare_abs_db.s");

    var out: [512]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "777\n-1\n0\n4\n1\n0\n1\n0\n77\n5\n77\n5\n77\n5\n77\n65536\n\n",
        out[0..result.output_len_bytes],
    );
}

test "engine executes compare pseudo immediate forms outside delay slots" {
    const program =
        \\.text
        \\main:
        \\    li    $t0, 5
        \\    seq   $s0, $t0, 5
        \\    sne   $s1, $t0, 5
        \\    sge   $s2, $t0, 5
        \\    sgt   $s3, $t0, 5
        \\    sle   $s4, $t0, 5
        \\
        \\    li    $t1, -1
        \\    sgeu  $s5, $t1, 5
        \\    li    $t2, 1
        \\    sgtu  $s6, $t2, -1
        \\    sleu  $s7, $t2, -1
        \\
        \\    move  $a0, $s0
        \\    jal   print_int_line
        \\    move  $a0, $s1
        \\    jal   print_int_line
        \\    move  $a0, $s2
        \\    jal   print_int_line
        \\    move  $a0, $s3
        \\    jal   print_int_line
        \\    move  $a0, $s4
        \\    jal   print_int_line
        \\    move  $a0, $s5
        \\    jal   print_int_line
        \\    move  $a0, $s6
        \\    jal   print_int_line
        \\    move  $a0, $s7
        \\    jal   print_int_line
        \\    li    $v0, 10
        \\    syscall
        \\print_int_line:
        \\    li    $v0, 1
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    jr    $ra
    ;

    var out: [128]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("1\n0\n1\n0\n1\n1\n0\n1\n", out[0..result.output_len_bytes]);
}

test "engine delayed-slot arithmetic and logical pseudo immediate forms execute first expansion word only" {
    const program = @embedFile("../../test_programs/delay_slot_pseudo_arith_logic_db.s");

    var out: [1024]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "15\n99\n65536\n99\n0\n99\n5\n99\n0\n99\n65536\n99\n65536\n99\n5\n99\n0\n52\n99\n65536\n99\n65536\n99\n65536\n99\n65536\n99\n65536\n\n",
        out[0..result.output_len_bytes],
    );
}

test "engine executes arithmetic and logical pseudo immediate forms outside delay slots" {
    const program =
        \\.text
        \\main:
        \\    li    $t0, 10
        \\    add   $s0, $t0, 100000
        \\    addu  $s1, $t0, 5
        \\    sub   $s2, $t0, 5
        \\    subu  $s3, $t0, 5
        \\    addi  $s4, $t0, 100000
        \\    addiu $s5, $t0, 100000
        \\    subi  $s6, $t0, 5
        \\    subiu $s7, $t0, 5
        \\    andi  $t1, $t0, 100000
        \\    ori   $t2, $t0, 100000
        \\    xori  $t3, $t0, 100000
        \\    andi  $t4, 100000
        \\    ori   $t5, 100000
        \\    xori  $t6, 100000
        \\    and   $t7, $t0, 255
        \\    or    $k0, $t0, 255
        \\    xor   $k1, $t0, 255
        \\
        \\    move  $a0, $s0
        \\    jal   print_int_line
        \\    move  $a0, $s1
        \\    jal   print_int_line
        \\    move  $a0, $s2
        \\    jal   print_int_line
        \\    move  $a0, $s3
        \\    jal   print_int_line
        \\    move  $a0, $s4
        \\    jal   print_int_line
        \\    move  $a0, $s5
        \\    jal   print_int_line
        \\    move  $a0, $s6
        \\    jal   print_int_line
        \\    move  $a0, $s7
        \\    jal   print_int_line
        \\    move  $a0, $t1
        \\    jal   print_int_line
        \\    move  $a0, $t2
        \\    jal   print_int_line
        \\    move  $a0, $t3
        \\    jal   print_int_line
        \\    move  $a0, $t4
        \\    jal   print_int_line
        \\    move  $a0, $t5
        \\    jal   print_int_line
        \\    move  $a0, $t6
        \\    jal   print_int_line
        \\    move  $a0, $t7
        \\    jal   print_int_line
        \\    move  $a0, $k0
        \\    jal   print_int_line
        \\    move  $a0, $k1
        \\    jal   print_int_line
        \\    li    $v0, 10
        \\    syscall
        \\print_int_line:
        \\    li    $v0, 1
        \\    syscall
        \\    li    $v0, 11
        \\    li    $a0, 10
        \\    syscall
        \\    jr    $ra
    ;

    var out: [512]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "100010\n15\n5\n5\n100010\n100010\n5\n5\n0\n100010\n100010\n0\n100010\n100010\n10\n255\n245\n",
        out[0..result.output_len_bytes],
    );
}

test "engine delayed-slot pseudo misc forms execute first expansion word only" {
    const program = @embedFile("../../test_programs/delay_slot_pseudo_misc_db.s");

    var out: [1024]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "99\n4194304\n99\n65536\n99\n-4\n99\n1\n99\n-4\n99\n-2147483648\n287454020\n88\n-1716864052\n0\n99\n5\n99\n65536\n99\n5\n123\n456\n99\n5\n123\n456\n\n",
        out[0..result.output_len_bytes],
    );
}

test "engine delayed-slot register-divisor div/rem pseudo forms execute first expansion word only" {
    const program = @embedFile("../../test_programs/delay_slot_pseudo_div_reg_db.s");

    var out: [512]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = true,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings(
        "99\n11\n22\n99\n33\n44\n99\n55\n66\n99\n77\n88\n99\n101\n202\n\n",
        out[0..result.output_len_bytes],
    );
}

test "engine unknown source mnemonic returns parse error" {
    const program =
        \\.text
        \\main:
        \\    frobnicate $t0, $t1, $t2
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.parse_error, result.status);
}

test "engine unknown syscall service returns runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $v0, 999
        \\    syscall
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = false,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

test "engine patched reserved opcode returns runtime error" {
    const program =
        \\.text
        \\main:
        \\    li   $t8, 0xFC000000
        \\    la   $t9, slot_bad
        \\    sw   $t8, 0($t9)
        \\    j    slot_bad
        \\slot_bad:
        \\    nop
    ;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });

    try std.testing.expectEqual(StatusCode.runtime_error, result.status);
}

fn run_patched_decode_failure_case(word: u32) StatusCode {
    // Build the patched instruction with `lui/ori` so every 32-bit word can be tested.
    const upper_imm: u16 = @intCast((word >> 16) & 0xFFFF);
    const lower_imm: u16 = @intCast(word & 0xFFFF);
    var program_buffer: [512]u8 = undefined;
    const program = std.fmt.bufPrint(
        &program_buffer,
        \\.text
        \\main:
        \\    lui  $t8, 0x{X:0>4}
        \\    ori  $t8, $t8, 0x{X:0>4}
        \\    la   $t9, slot_bad
        \\    sw   $t8, 0($t9)
        \\    j    slot_bad
        \\slot_bad:
        \\    nop
        \\
    ,
        .{ upper_imm, lower_imm },
    ) catch unreachable;

    var out: [64]u8 = undefined;
    const result = run_program(program, out[0..], .{
        .delayed_branching_enabled = false,
        .smc_enabled = true,
        .input_text = "",
    });
    return result.status;
}

test "engine patched regimm unknown rt returns runtime error" {
    // opcode=0x01, rt=0x02 is unassigned in REGIMM decode.
    const status = run_patched_decode_failure_case(0x0402_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop0 unknown rs returns runtime error" {
    // opcode=0x10 with rs=0x1F is outside mfc0/mtc0/eret handling.
    const status = run_patched_decode_failure_case(0x43E0_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop1 branch likely form returns runtime error" {
    // opcode=0x11, rs=0x08, rt bit1 set corresponds to unsupported bc1fl/bc1tl forms.
    const status = run_patched_decode_failure_case(0x4502_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop1 fmt.s unknown funct returns runtime error" {
    // opcode=0x11, rs=0x10, funct=0x08 is not implemented for fmt.s in MARS core decode.
    const status = run_patched_decode_failure_case(0x4600_0008);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop1 fmt.d unknown funct returns runtime error" {
    // opcode=0x11, rs=0x11, funct=0x08 is not a valid fmt.d operation.
    const status = run_patched_decode_failure_case(0x4620_0008);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop1 fmt.w unknown funct returns runtime error" {
    // opcode=0x11, rs=0x14, funct=0x00 is outside cvt.s.w/cvt.d.w.
    const status = run_patched_decode_failure_case(0x4680_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched cop1 unknown rs returns runtime error" {
    // opcode=0x11, rs=0x1E is not a supported cop1 transfer/arithmetic group.
    const status = run_patched_decode_failure_case(0x47C0_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched unknown primary opcode returns runtime error" {
    // opcode=0x3F has no architectural decode in this runtime.
    const status = run_patched_decode_failure_case(0xFC00_0000);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched special unknown funct returns runtime error" {
    // opcode=0x00 with funct=0x3F is outside this runtime's SPECIAL decode table.
    const status = run_patched_decode_failure_case(0x0000_003F);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}

test "engine patched special2 unknown funct returns runtime error" {
    // opcode=0x1C with funct=0x3F is outside this runtime's SPECIAL2 decode table.
    const status = run_patched_decode_failure_case(0x7000_003F);
    try std.testing.expectEqual(StatusCode.runtime_error, status);
}
