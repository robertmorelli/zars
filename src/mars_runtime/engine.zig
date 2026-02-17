const std = @import("std");
const assert = std.debug.assert;
const fp_math = @import("fp_math.zig");
const operand_parse = @import("operand_parse.zig");
const source_preprocess = @import("source_preprocess.zig");
const syscall_dispatch = @import("instructions/syscall_dispatch.zig");
const model = @import("model.zig");
const engine_data = @import("engine_data.zig");

pub const max_instruction_count = model.max_instruction_count;
pub const max_label_count = model.max_label_count;
pub const max_token_len = model.max_token_len;
pub const data_capacity_bytes = model.data_capacity_bytes;
pub const max_text_word_count = model.max_text_word_count;
pub const max_fixup_count = model.max_fixup_count;
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
const Fixup = model.Fixup;
const FixupKind = model.FixupKind;
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

const reg_at: u5 = 1;

// Centralized bit masks to prevent duplication.
const mask_u16: u32 = 0xFFFF;
const mask_u32: u32 = 0xFFFF_FFFF;
const mask_shift_amount: u32 = 0x1F;
const bits_per_word: u32 = 32;
const bits_per_halfword: u32 = 16;

const register_names = [_][]const u8{
    "$zero", "$at", "$v0", "$v1", "$a0", "$a1", "$a2", "$a3",
    "$t0",   "$t1", "$t2", "$t3", "$t4", "$t5", "$t6", "$t7",
    "$s0",   "$s1", "$s2", "$s3", "$s4", "$s5", "$s6", "$s7",
    "$t8",   "$t9", "$k0", "$k1", "$gp", "$sp", "$fp", "$ra",
};

// Centralized directive names to prevent string literal duplication.
const directives = struct {
    const text = ".text";
    const ktext = ".ktext";
    const data = ".data";
    const kdata = ".kdata";
    const globl = ".globl";
    const extern_dir = ".extern";
    const set_dir = ".set";
    const align_dir = ".align";
    const asciiz = ".asciiz";
    const ascii = ".ascii";
    const space = ".space";
    const byte = ".byte";
    const half = ".half";
    const word = ".word";
    const float_dir = ".float";
    const double_dir = ".double";
};

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
    // ===================================================================
    // PARSER: Line-oriented source parsing with label/directive handling
    // ===================================================================
    // Reset all parser-owned tables before each run.
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

    // Parser is line-oriented because MARS source format and directives are line-oriented.
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
    if (!resolve_fixups(parsed)) return .parse_error;
    return .ok;
}

fn align_for_data_directive(parsed: *Program, directive_line: []const u8) !void {
    // Data labels should point at post-alignment addresses just like MARS.
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

    if (std.mem.startsWith(u8, directive_line, directives.ascii)) {
        const rest = operand_parse.trim_ascii(directive_line[directives.ascii.len..]);
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

    if (std.mem.startsWith(u8, directive_line, directives.globl)) {
        return true;
    }

    if (std.mem.startsWith(u8, directive_line, directives.extern_dir)) {
        return true;
    }

    if (std.mem.startsWith(u8, directive_line, directives.set_dir)) {
        return true;
    }

    return false;
}

fn register_name(reg: u5) []const u8 {
    return register_names[reg];
}

fn add_fixup(
    parsed: *Program,
    label_name: []const u8,
    offset: i32,
    instruction_index: u32,
    operand_index: u8,
    kind: FixupKind,
) bool {
    if (parsed.fixup_count >= max_fixup_count) return false;
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

/// Extract high 16 bits of a 32-bit value.
fn extract_high_bits(value: i32) i32 {
    const value_u32: u32 = @bitCast(value);
    return @bitCast((value_u32 >> bits_per_halfword) & mask_u16);
}

/// Extract low 16 bits of a 32-bit value.
fn extract_low_bits(value: i32) i32 {
    const value_u32: u32 = @bitCast(value);
    return @bitCast(value_u32 & mask_u16);
}

/// Load high bits only of an immediate into $at (delay slot helper).
fn load_at_high_bits_only(state: *ExecState, imm: i32) void {
    const imm_bits: u32 = @bitCast(imm);
    const high_only: u32 = imm_bits & 0xFFFF_0000;
    write_reg(state, reg_at, @bitCast(high_only));
}

/// Bitwise operation helper - reduces duplication for and/or/xor operations.
/// Supports both register and immediate operands with 2 or 3 operand forms.
fn execute_bitwise_op(
    state: *ExecState,
    instruction: *const LineInstruction,
    comptime op_fn: fn (u32, u32) u32,
) StatusCode {
    if (instruction.operand_count == 3) {
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const rs = operand_parse.parse_register(instruction_operand(instruction, 1)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rs));
        if (operand_parse.parse_register(instruction_operand(instruction, 2))) |rt| {
            const rhs: u32 = @bitCast(read_reg(state, rt));
            write_reg(state, rd, @bitCast(op_fn(lhs, rhs)));
            return .ok;
        }
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return .parse_error;
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
        const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return .parse_error;
        const lhs: u32 = @bitCast(read_reg(state, rd));
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return .parse_error;
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

/// Bitwise AND operation.
fn bitwise_and(a: u32, b: u32) u32 {
    return a & b;
}

/// Bitwise OR operation.
fn bitwise_or(a: u32, b: u32) u32 {
    return a | b;
}

/// Bitwise XOR operation.
fn bitwise_xor(a: u32, b: u32) u32 {
    return a ^ b;
}

fn resolve_fixups(parsed: *Program) bool {
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

/// Emit a 32-bit immediate load into $at using lui + ori.
/// Returns false if emission fails.
fn emit_load_immediate_at(parsed: *Program, imm: i32) bool {
    const high = extract_high_bits(imm);
    const low = extract_low_bits(imm);
    var high_str: [32]u8 = undefined;
    var low_str: [32]u8 = undefined;
    const high_text = std.fmt.bufPrint(&high_str, "{}", .{high}) catch return false;
    const low_text = std.fmt.bufPrint(&low_str, "{}", .{low}) catch return false;
    if (!emit_instruction(parsed, "lui", &[_][]const u8{ "$at", high_text })) return false;
    return emit_instruction(parsed, "ori", &[_][]const u8{ "$at", "$at", low_text });
}

fn emit_load_at_signed(parsed: *Program, imm: i32) bool {
    if (immediate_fits_signed_16(imm)) {
        var imm_str: [32]u8 = undefined;
        const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return false;
        return emit_instruction(parsed, "addi", &[_][]const u8{ "$at", "$zero", imm_text });
    }
    return emit_load_immediate_at(parsed, imm);
}

fn emit_load_at_unsigned(parsed: *Program, imm: i32) bool {
    if (immediate_fits_unsigned_16(imm)) {
        var imm_str: [32]u8 = undefined;
        const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return false;
        return emit_instruction(parsed, "ori", &[_][]const u8{ "$at", "$zero", imm_text });
    }
    return emit_load_immediate_at(parsed, imm);
}

/// Single source of truth for pseudo-op expansion and word count estimation.
///
/// When emit=true: expands pseudo-ops into basic instructions in parsed.
///   Returns word count on success, null if not a pseudo-op or expansion failed.
/// When emit=false: returns the word count for pseudo-ops without modifying program.
///   Returns null for basic (non-pseudo) instructions.
///
/// This function eliminates the prior three-way duplication between
/// try_expand_pseudo_op(), estimate_instruction_word_count(), and
/// execute_instruction() by serving as the single authoritative source
/// for expansion decisions and word counts.
/// ===================================================================
/// PSEUDO-OP EXPANSION: Central handler for all pseudo-instruction patterns
/// This maintains single source of truth to avoid duplication between
/// parse-time expansion, count estimation, and execution semantics
/// ===================================================================
fn process_pseudo_op(parsed_opt: ?*Program, instruction: *const LineInstruction, emit: bool) ?u32 {
    const op = instruction.op[0..instruction.op_len];

    // ===================================================================
    // Expandable pseudo-ops (both emit and count modes work)
    // ===================================================================

    // li: Load Immediate
    if (std.mem.eql(u8, op, "li")) {
        if (instruction.operand_count != 2) return if (!emit) @as(?u32, 1) else null;
        const rd_text = instruction_operand(instruction, 0);
        const imm_text = instruction_operand(instruction, 1);
        const imm = operand_parse.parse_immediate(imm_text) orelse
            return if (!emit) @as(?u32, 1) else null;

        // Negative and fits in signed 16 bits -> addiu (sign-extend), 1 word
        if (imm >= std.math.minInt(i16) and imm < 0) {
            if (emit) {
                if (!emit_instruction(parsed_opt.?, "addiu", &[_][]const u8{ rd_text, "$zero", imm_text })) return null;
            }
            return 1;
        }
        // Non-negative and fits in unsigned 16 bits -> ori (zero-extend), 1 word
        if (imm >= 0 and imm <= std.math.maxInt(u16)) {
            if (emit) {
                if (!emit_instruction(parsed_opt.?, "ori", &[_][]const u8{ rd_text, "$zero", imm_text })) return null;
            }
            return 1;
        }
        // 32-bit immediate -> lui $at, high + ori rd, $at, low, 2 words
        if (emit) {
            const parsed = parsed_opt.?;
            const high = extract_high_bits(imm);
            const low = extract_low_bits(imm);
            var high_str: [32]u8 = undefined;
            var low_str: [32]u8 = undefined;
            const high_text = std.fmt.bufPrint(&high_str, "{}", .{high}) catch return null;
            const low_text = std.fmt.bufPrint(&low_str, "{}", .{low}) catch return null;
            if (!emit_instruction(parsed, "lui", &[_][]const u8{ "$at", high_text })) return null;
            if (!emit_instruction(parsed, "ori", &[_][]const u8{ rd_text, "$at", low_text })) return null;
        }
        return 2;
    }

    // move: Move register -> addu rd, rs, $zero
    if (std.mem.eql(u8, op, "move")) {
        if (instruction.operand_count != 2) return if (!emit) @as(?u32, 1) else null;
        if (emit) {
            const rd_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_instruction(parsed_opt.?, "addu", &[_][]const u8{ rd_text, rs_text, "$zero" })) return null;
        }
        return 1;
    }

    // b: Unconditional branch -> beq $zero, $zero, label
    if (std.mem.eql(u8, op, "b")) {
        if (instruction.operand_count != 1) return if (!emit) @as(?u32, 1) else null;
        if (emit) {
            const label = instruction_operand(instruction, 0);
            if (!emit_instruction(parsed_opt.?, "beq", &[_][]const u8{ "$zero", "$zero", label })) return null;
        }
        return 1;
    }

    // beqz: Branch if equal zero -> beq $rs, $zero, label
    if (std.mem.eql(u8, op, "beqz")) {
        if (instruction.operand_count != 2) return if (!emit) @as(?u32, 1) else null;
        if (emit) {
            const rs_text = instruction_operand(instruction, 0);
            const label = instruction_operand(instruction, 1);
            if (!emit_instruction(parsed_opt.?, "beq", &[_][]const u8{ rs_text, "$zero", label })) return null;
        }
        return 1;
    }

    // bnez: Branch if not equal zero -> bne $rs, $zero, label
    if (std.mem.eql(u8, op, "bnez")) {
        if (instruction.operand_count != 2) return if (!emit) @as(?u32, 1) else null;
        if (emit) {
            const rs_text = instruction_operand(instruction, 0);
            const label = instruction_operand(instruction, 1);
            if (!emit_instruction(parsed_opt.?, "bne", &[_][]const u8{ rs_text, "$zero", label })) return null;
        }
        return 1;
    }

    // la: Load address
    if (std.mem.eql(u8, op, "la")) {
        if (instruction.operand_count != 2) return if (!emit) @as(?u32, 1) else null;

        const rd_text = instruction_operand(instruction, 0);
        const address_text = instruction_operand(instruction, 1);
        const address_operand = parse_address_operand(address_text) orelse
            return if (!emit) @as(?u32, 1) else null;

        const has_base = address_operand.base_register != null;
        switch (address_operand.expression) {
            .empty => {
                if (!has_base) return if (!emit) @as(?u32, 1) else null;
                if (emit) {
                    const base_text = register_name(address_operand.base_register.?);
                    if (!emit_instruction(parsed_opt.?, "addi", &[_][]const u8{ rd_text, base_text, "0" })) return null;
                }
                return 1;
            },
            .immediate => |imm| {
                if (!has_base) {
                    if (imm >= std.math.minInt(i16) and imm < 0) {
                        if (emit) {
                            var imm_str: [32]u8 = undefined;
                            const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                            if (!emit_instruction(parsed_opt.?, "addiu", &[_][]const u8{ rd_text, "$zero", imm_text })) return null;
                        }
                        return 1;
                    }
                    if (imm >= 0 and imm <= std.math.maxInt(u16)) {
                        if (emit) {
                            var imm_str: [32]u8 = undefined;
                            const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                            if (!emit_instruction(parsed_opt.?, "ori", &[_][]const u8{ rd_text, "$zero", imm_text })) return null;
                        }
                        return 1;
                    }
                    if (emit) {
                        const high = extract_high_bits(imm);
                        const low = extract_low_bits(imm);
                        var high_str: [32]u8 = undefined;
                        var low_str: [32]u8 = undefined;
                        const high_text = std.fmt.bufPrint(&high_str, "{}", .{high}) catch return null;
                        const low_text = std.fmt.bufPrint(&low_str, "{}", .{low}) catch return null;
                        if (!emit_instruction(parsed_opt.?, "lui", &[_][]const u8{ "$at", high_text })) return null;
                        if (!emit_instruction(parsed_opt.?, "ori", &[_][]const u8{ rd_text, "$at", low_text })) return null;
                    }
                    return 2;
                }

                if (immediate_fits_unsigned_16(imm)) {
                    if (emit) {
                        var imm_str: [32]u8 = undefined;
                        const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                        const base_text = register_name(address_operand.base_register.?);
                        if (!emit_instruction(parsed_opt.?, "ori", &[_][]const u8{ "$at", "$zero", imm_text })) return null;
                        if (!emit_instruction(parsed_opt.?, "add", &[_][]const u8{ rd_text, base_text, "$at" })) return null;
                    }
                    return 2;
                }

                if (emit) {
                    const base_text = register_name(address_operand.base_register.?);
                    if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
                    if (!emit_instruction(parsed_opt.?, "add", &[_][]const u8{ rd_text, base_text, "$at" })) return null;
                }
                return 3;
            },
            .label => |label_name| {
                if (emit) {
                    const parsed = parsed_opt.?;
                    if (!emit_instruction(parsed, "lui", &[_][]const u8{ "$at", "0" })) return null;
                    if (!add_fixup(parsed, label_name, 0, parsed.instruction_count - 1, 1, .hi_no_carry)) return null;
                    if (has_base) {
                        if (!emit_instruction(parsed, "ori", &[_][]const u8{ "$at", "$at", "0" })) return null;
                        if (!add_fixup(parsed, label_name, 0, parsed.instruction_count - 1, 2, .lo_unsigned)) return null;
                        const base_text = register_name(address_operand.base_register.?);
                        if (!emit_instruction(parsed, "add", &[_][]const u8{ rd_text, base_text, "$at" })) return null;
                    } else {
                        if (!emit_instruction(parsed, "ori", &[_][]const u8{ rd_text, "$at", "0" })) return null;
                        if (!add_fixup(parsed, label_name, 0, parsed.instruction_count - 1, 2, .lo_unsigned)) return null;
                    }
                }
                return if (has_base) 3 else 2;
            },
            .label_plus_offset => |label_offset| {
                if (emit) {
                    const parsed = parsed_opt.?;
                    if (!emit_instruction(parsed, "lui", &[_][]const u8{ "$at", "0" })) return null;
                    if (!add_fixup(parsed, label_offset.label_name, label_offset.offset, parsed.instruction_count - 1, 1, .hi_no_carry)) return null;
                    if (has_base) {
                        if (!emit_instruction(parsed, "ori", &[_][]const u8{ "$at", "$at", "0" })) return null;
                        if (!add_fixup(parsed, label_offset.label_name, label_offset.offset, parsed.instruction_count - 1, 2, .lo_unsigned)) return null;
                        const base_text = register_name(address_operand.base_register.?);
                        if (!emit_instruction(parsed, "add", &[_][]const u8{ rd_text, base_text, "$at" })) return null;
                    } else {
                        if (!emit_instruction(parsed, "ori", &[_][]const u8{ rd_text, "$at", "0" })) return null;
                        if (!add_fixup(parsed, label_offset.label_name, label_offset.offset, parsed.instruction_count - 1, 2, .lo_unsigned)) return null;
                    }
                }
                return if (has_base) 3 else 2;
            },
            .invalid => return if (!emit) @as(?u32, 1) else null,
        }
    }

    if (std.mem.eql(u8, op, "neg")) {
        if (instruction.operand_count != 2) return if (!emit) @as(?u32, 1) else null;
        if (emit) {
            const rd_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_instruction(parsed_opt.?, "sub", &[_][]const u8{ rd_text, "$zero", rs_text })) return null;
        }
        return 1;
    }

    if (std.mem.eql(u8, op, "negu")) {
        if (instruction.operand_count != 2) return if (!emit) @as(?u32, 1) else null;
        if (emit) {
            const rd_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_instruction(parsed_opt.?, "subu", &[_][]const u8{ rd_text, "$zero", rs_text })) return null;
        }
        return 1;
    }

    if (std.mem.eql(u8, op, "abs")) {
        if (instruction.operand_count != 2) return if (!emit) @as(?u32, 1) else null;
        if (emit) {
            const rd_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_instruction(parsed_opt.?, "sra", &[_][]const u8{ "$at", rs_text, "31" })) return null;
            if (!emit_instruction(parsed_opt.?, "xor", &[_][]const u8{ rd_text, "$at", rs_text })) return null;
            if (!emit_instruction(parsed_opt.?, "subu", &[_][]const u8{ rd_text, rd_text, "$at" })) return null;
        }
        return 3;
    }

    if (std.mem.eql(u8, op, "addi")) {
        if (instruction.operand_count != 3) return if (!emit) @as(?u32, 1) else null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse
            return if (!emit) @as(?u32, 1) else null;
        if (immediate_fits_signed_16(imm)) return null;

        if (emit) {
            const rt_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
            if (!emit_instruction(parsed_opt.?, "add", &[_][]const u8{ rt_text, rs_text, "$at" })) return null;
        }
        return 3;
    }

    if (std.mem.eql(u8, op, "addiu")) {
        if (instruction.operand_count != 3) return if (!emit) @as(?u32, 1) else null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse
            return if (!emit) @as(?u32, 1) else null;
        if (immediate_fits_signed_16(imm)) return null;

        if (emit) {
            const rt_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
            if (!emit_instruction(parsed_opt.?, "addu", &[_][]const u8{ rt_text, rs_text, "$at" })) return null;
        }
        return 3;
    }

    if (std.mem.eql(u8, op, "subi")) {
        if (instruction.operand_count != 3) return if (!emit) @as(?u32, 1) else null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse
            return if (!emit) @as(?u32, 1) else null;
        if (emit) {
            const rt_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (immediate_fits_signed_16(imm)) {
                var imm_str: [32]u8 = undefined;
                const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                if (!emit_instruction(parsed_opt.?, "addi", &[_][]const u8{ "$at", "$zero", imm_text })) return null;
                if (!emit_instruction(parsed_opt.?, "sub", &[_][]const u8{ rt_text, rs_text, "$at" })) return null;
                return 2;
            }
            if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
            if (!emit_instruction(parsed_opt.?, "sub", &[_][]const u8{ rt_text, rs_text, "$at" })) return null;
        }
        return if (immediate_fits_signed_16(imm)) 2 else 3;
    }

    if (std.mem.eql(u8, op, "subiu")) {
        if (instruction.operand_count != 3) return if (!emit) @as(?u32, 1) else null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse
            return if (!emit) @as(?u32, 1) else null;
        // MARS always expands subiu to lui + ori + subu, even for small immediates.
        if (emit) {
            const rt_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
            if (!emit_instruction(parsed_opt.?, "subu", &[_][]const u8{ rt_text, rs_text, "$at" })) return null;
        }
        return 3;
    }

    if (std.mem.eql(u8, op, "add")) {
        if (instruction.operand_count != 3) return null;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
        if (immediate_fits_signed_16(imm)) {
            if (!emit) return 1;
            const rd_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            var imm_str: [32]u8 = undefined;
            const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
            if (!emit_instruction(parsed_opt.?, "addi", &[_][]const u8{ rd_text, rs_text, imm_text })) return null;
            return 1;
        }
        if (emit) {
            const rd_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
            if (!emit_instruction(parsed_opt.?, "add", &[_][]const u8{ rd_text, rs_text, "$at" })) return null;
        }
        return 3;
    }

    if (std.mem.eql(u8, op, "addu")) {
        if (instruction.operand_count != 3) return null;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
        if (immediate_fits_signed_16(imm)) return null;
        if (emit) {
            const rd_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
            if (!emit_instruction(parsed_opt.?, "addu", &[_][]const u8{ rd_text, rs_text, "$at" })) return null;
        }
        return 3;
    }

    if (std.mem.eql(u8, op, "sub")) {
        if (instruction.operand_count != 3) return null;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
        if (immediate_fits_signed_16(imm)) {
            if (!emit) return 2;
            const rd_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            var imm_str: [32]u8 = undefined;
            const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
            if (!emit_instruction(parsed_opt.?, "addi", &[_][]const u8{ "$at", "$zero", imm_text })) return null;
            if (!emit_instruction(parsed_opt.?, "sub", &[_][]const u8{ rd_text, rs_text, "$at" })) return null;
            return 2;
        }
        if (emit) {
            const rd_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
            if (!emit_instruction(parsed_opt.?, "sub", &[_][]const u8{ rd_text, rs_text, "$at" })) return null;
        }
        return 3;
    }

    if (std.mem.eql(u8, op, "subu")) {
        if (instruction.operand_count != 3) return null;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
        if (immediate_fits_signed_16(imm)) return null;
        if (emit) {
            const rd_text = instruction_operand(instruction, 0);
            const rs_text = instruction_operand(instruction, 1);
            if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
            if (!emit_instruction(parsed_opt.?, "subu", &[_][]const u8{ rd_text, rs_text, "$at" })) return null;
        }
        return 3;
    }

    if (std.mem.eql(u8, op, "and") or std.mem.eql(u8, op, "or") or std.mem.eql(u8, op, "xor")) {
        if (instruction.operand_count == 3) {
            if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return null;
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
            const op_text = if (std.mem.eql(u8, op, "and")) "andi" else if (std.mem.eql(u8, op, "or")) "ori" else "xori";
            if (immediate_fits_unsigned_16(imm)) {
                if (!emit) return 1;
                const rd_text = instruction_operand(instruction, 0);
                const rs_text = instruction_operand(instruction, 1);
                var imm_str: [32]u8 = undefined;
                const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                if (!emit_instruction(parsed_opt.?, op_text, &[_][]const u8{ rd_text, rs_text, imm_text })) return null;
                return 1;
            }
            if (emit) {
                const rd_text = instruction_operand(instruction, 0);
                const rs_text = instruction_operand(instruction, 1);
                if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
                if (!emit_instruction(parsed_opt.?, op, &[_][]const u8{ rd_text, rs_text, "$at" })) return null;
            }
            return 3;
        }
        if (instruction.operand_count == 2) {
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return null;
            const op_text = if (std.mem.eql(u8, op, "and")) "andi" else if (std.mem.eql(u8, op, "or")) "ori" else "xori";
            if (immediate_fits_unsigned_16(imm)) {
                if (!emit) return 1;
                const rd_text = instruction_operand(instruction, 0);
                var imm_str: [32]u8 = undefined;
                const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                if (!emit_instruction(parsed_opt.?, op_text, &[_][]const u8{ rd_text, rd_text, imm_text })) return null;
                return 1;
            }
            if (emit) {
                const rd_text = instruction_operand(instruction, 0);
                if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
                if (!emit_instruction(parsed_opt.?, op, &[_][]const u8{ rd_text, rd_text, "$at" })) return null;
            }
            return 3;
        }
        return null;
    }

    if (std.mem.eql(u8, op, "andi") or std.mem.eql(u8, op, "ori") or std.mem.eql(u8, op, "xori")) {
        if (instruction.operand_count == 2) {
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return null;
            if (immediate_fits_unsigned_16(imm)) {
                if (!emit) return 1;
                const rt_text = instruction_operand(instruction, 0);
                var imm_str: [32]u8 = undefined;
                const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                if (!emit_instruction(parsed_opt.?, op, &[_][]const u8{ rt_text, rt_text, imm_text })) return null;
                return 1;
            }
            if (emit) {
                const rt_text = instruction_operand(instruction, 0);
                if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
                const op_text = if (std.mem.eql(u8, op, "andi")) "and" else if (std.mem.eql(u8, op, "ori")) "or" else "xor";
                if (!emit_instruction(parsed_opt.?, op_text, &[_][]const u8{ rt_text, rt_text, "$at" })) return null;
            }
            return 3;
        }
        if (instruction.operand_count == 3) {
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
            if (immediate_fits_unsigned_16(imm)) return null;
            if (emit) {
                const rt_text = instruction_operand(instruction, 0);
                const rs_text = instruction_operand(instruction, 1);
                if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
                const op_text = if (std.mem.eql(u8, op, "andi")) "and" else if (std.mem.eql(u8, op, "ori")) "or" else "xor";
                if (!emit_instruction(parsed_opt.?, op_text, &[_][]const u8{ rt_text, rs_text, "$at" })) return null;
            }
            return 3;
        }
        return null;
    }

    if (std.mem.eql(u8, op, "beq") or std.mem.eql(u8, op, "bne")) {
        if (instruction.operand_count != 3) return null;
        if (operand_parse.parse_register(instruction_operand(instruction, 1)) != null) return null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return null;
        if (emit) {
            const rs_text = instruction_operand(instruction, 0);
            const label_text = instruction_operand(instruction, 2);
            if (immediate_fits_signed_16(imm)) {
                var imm_str: [32]u8 = undefined;
                const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                if (!emit_instruction(parsed_opt.?, "addi", &[_][]const u8{ "$at", "$zero", imm_text })) return null;
            } else {
                if (!emit_load_immediate_at(parsed_opt.?, imm)) return null;
            }
            if (!emit_instruction(parsed_opt.?, op, &[_][]const u8{ "$at", rs_text, label_text })) return null;
        }
        return if (immediate_fits_signed_16(imm)) 2 else 3;
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
        if (instruction.operand_count != 3) return if (!emit) @as(?u32, 1) else null;
        const rs_text = instruction_operand(instruction, 0);
        const rhs_text = instruction_operand(instruction, 1);
        const label_text = instruction_operand(instruction, 2);

        if (operand_parse.parse_register(rhs_text)) |rt| {
            if (emit) {
                const rt_text = register_name(rt);
                if (std.mem.eql(u8, op, "blt")) {
                    if (!emit_instruction(parsed_opt.?, "slt", &[_][]const u8{ "$at", rs_text, rt_text })) return null;
                    if (!emit_instruction(parsed_opt.?, "bne", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                } else if (std.mem.eql(u8, op, "bltu")) {
                    if (!emit_instruction(parsed_opt.?, "sltu", &[_][]const u8{ "$at", rs_text, rt_text })) return null;
                    if (!emit_instruction(parsed_opt.?, "bne", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                } else if (std.mem.eql(u8, op, "bge")) {
                    if (!emit_instruction(parsed_opt.?, "slt", &[_][]const u8{ "$at", rs_text, rt_text })) return null;
                    if (!emit_instruction(parsed_opt.?, "beq", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                } else if (std.mem.eql(u8, op, "bgeu")) {
                    if (!emit_instruction(parsed_opt.?, "sltu", &[_][]const u8{ "$at", rs_text, rt_text })) return null;
                    if (!emit_instruction(parsed_opt.?, "beq", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                } else if (std.mem.eql(u8, op, "bgt")) {
                    if (!emit_instruction(parsed_opt.?, "slt", &[_][]const u8{ "$at", rt_text, rs_text })) return null;
                    if (!emit_instruction(parsed_opt.?, "bne", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                } else if (std.mem.eql(u8, op, "bgtu")) {
                    if (!emit_instruction(parsed_opt.?, "sltu", &[_][]const u8{ "$at", rt_text, rs_text })) return null;
                    if (!emit_instruction(parsed_opt.?, "bne", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                } else if (std.mem.eql(u8, op, "ble")) {
                    if (!emit_instruction(parsed_opt.?, "slt", &[_][]const u8{ "$at", rt_text, rs_text })) return null;
                    if (!emit_instruction(parsed_opt.?, "beq", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                } else if (std.mem.eql(u8, op, "bleu")) {
                    if (!emit_instruction(parsed_opt.?, "sltu", &[_][]const u8{ "$at", rt_text, rs_text })) return null;
                    if (!emit_instruction(parsed_opt.?, "beq", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                }
            }
            return 2;
        }

        const imm = operand_parse.parse_immediate(rhs_text) orelse return if (!emit) @as(?u32, 1) else null;
        const imm_fits = immediate_fits_signed_16(imm);
        if (emit) {
            if (std.mem.eql(u8, op, "blt") or std.mem.eql(u8, op, "bge")) {
                if (imm_fits) {
                    var imm_str: [32]u8 = undefined;
                    const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                    if (!emit_instruction(parsed_opt.?, "slti", &[_][]const u8{ "$at", rs_text, imm_text })) return null;
                } else {
                    if (!emit_load_at_signed(parsed_opt.?, imm)) return null;
                    if (!emit_instruction(parsed_opt.?, "slt", &[_][]const u8{ "$at", rs_text, "$at" })) return null;
                }
                const branch_op = if (std.mem.eql(u8, op, "blt")) "bne" else "beq";
                if (!emit_instruction(parsed_opt.?, branch_op, &[_][]const u8{ "$at", "$zero", label_text })) return null;
            } else if (std.mem.eql(u8, op, "bltu") or std.mem.eql(u8, op, "bgeu")) {
                if (imm_fits) {
                    var imm_str: [32]u8 = undefined;
                    const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                    if (!emit_instruction(parsed_opt.?, "sltiu", &[_][]const u8{ "$at", rs_text, imm_text })) return null;
                } else {
                    if (!emit_load_at_unsigned(parsed_opt.?, imm)) return null;
                    if (!emit_instruction(parsed_opt.?, "sltu", &[_][]const u8{ "$at", rs_text, "$at" })) return null;
                }
                const branch_op = if (std.mem.eql(u8, op, "bltu")) "bne" else "beq";
                if (!emit_instruction(parsed_opt.?, branch_op, &[_][]const u8{ "$at", "$zero", label_text })) return null;
            } else if (std.mem.eql(u8, op, "bgt") or std.mem.eql(u8, op, "ble")) {
                if (imm_fits) {
                    var imm_str: [32]u8 = undefined;
                    const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                    if (std.mem.eql(u8, op, "ble")) {
                        if (!emit_instruction(parsed_opt.?, "addi", &[_][]const u8{ "$at", rs_text, "-1" })) return null;
                        if (!emit_instruction(parsed_opt.?, "slti", &[_][]const u8{ "$at", "$at", imm_text })) return null;
                        if (!emit_instruction(parsed_opt.?, "bne", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                    } else {
                        if (!emit_instruction(parsed_opt.?, "addi", &[_][]const u8{ "$at", "$zero", imm_text })) return null;
                        if (!emit_instruction(parsed_opt.?, "slt", &[_][]const u8{ "$at", "$at", rs_text })) return null;
                        if (!emit_instruction(parsed_opt.?, "bne", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                    }
                } else {
                    const imm_plus_one = imm +% 1;
                    if (!emit_load_at_unsigned(parsed_opt.?, imm_plus_one)) return null;
                    if (std.mem.eql(u8, op, "bgt")) {
                        if (!emit_instruction(parsed_opt.?, "slt", &[_][]const u8{ "$at", rs_text, "$at" })) return null;
                        if (!emit_instruction(parsed_opt.?, "beq", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                    } else {
                        if (!emit_instruction(parsed_opt.?, "slt", &[_][]const u8{ "$at", rs_text, "$at" })) return null;
                        if (!emit_instruction(parsed_opt.?, "bne", &[_][]const u8{ "$at", "$zero", label_text })) return null;
                    }
                }
            } else if (std.mem.eql(u8, op, "bgtu") or std.mem.eql(u8, op, "bleu")) {
                if (imm_fits) {
                    var imm_str: [32]u8 = undefined;
                    const imm_text = std.fmt.bufPrint(&imm_str, "{}", .{imm}) catch return null;
                    if (!emit_instruction(parsed_opt.?, "addi", &[_][]const u8{ "$at", "$zero", imm_text })) return null;
                } else {
                    if (!emit_load_at_unsigned(parsed_opt.?, imm)) return null;
                }
                if (!emit_instruction(parsed_opt.?, "sltu", &[_][]const u8{ "$at", "$at", rs_text })) return null;
                const branch_op = if (std.mem.eql(u8, op, "bgtu")) "bne" else "beq";
                if (!emit_instruction(parsed_opt.?, branch_op, &[_][]const u8{ "$at", "$zero", label_text })) return null;
            }
        }

        if (std.mem.eql(u8, op, "bgt") or std.mem.eql(u8, op, "bgtu") or std.mem.eql(u8, op, "ble") or std.mem.eql(u8, op, "bleu")) {
            return if (imm_fits) 3 else 4;
        }
        return if (imm_fits) 2 else 4;
    }

    // ===================================================================
    // Count-only pseudo-ops (emit returns null, count returns word count)
    // These will be progressively migrated to full expansion.
    // ===================================================================

    // For count-only ops, emit mode returns null (not expanded).
    if (emit) {
        // Check if this is a pseudo-op we recognize but can't expand yet.
        // If so, return null so the caller stores it as-is for execute_instruction.
        // The count-only path below handles estimation.
        //
        // We need to check all pseudo-ops here so that the function returns null
        // (not-a-pseudo) only for genuine basic instructions.
        if (is_count_only_pseudo_op(op)) return null;
        return null; // basic instruction (not a pseudo-op)
    }

    // --- Count-only estimation (emit=false path) ---

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
        if (instruction.operand_count != 3) return null;
        if (operand_parse.parse_register(instruction_operand(instruction, 1)) != null) return null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return null;
        if (immediate_fits_signed_16(imm)) return 2;
        return 3;
    }

    if (std.mem.eql(u8, op, "addi")) {
        if (instruction.operand_count != 3) return null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
        if (immediate_fits_signed_16(imm)) return null;
        return 3;
    }

    if (std.mem.eql(u8, op, "addiu")) {
        if (instruction.operand_count != 3) return null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
        if (immediate_fits_signed_16(imm)) return null;
        return 3;
    }

    if (std.mem.eql(u8, op, "subi")) {
        if (instruction.operand_count != 3) return 1;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        if (immediate_fits_signed_16(imm)) return 2;
        return 3;
    }

    if (std.mem.eql(u8, op, "subiu")) {
        if (instruction.operand_count != 3) return 1;
        _ = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return 1;
        // MARS always expands subiu to lui + ori + subu, even for small immediates.
        return 3;
    }

    if (std.mem.eql(u8, op, "andi") or std.mem.eql(u8, op, "ori") or std.mem.eql(u8, op, "xori")) {
        if (instruction.operand_count == 3) {
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
            if (immediate_fits_unsigned_16(imm)) return null;
            return 3;
        }
        if (instruction.operand_count == 2) {
            const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return null;
            if (immediate_fits_unsigned_16(imm)) return null;
            return 3;
        }
        return null;
    }

    if (std.mem.eql(u8, op, "abs")) {
        if (instruction.operand_count != 2) return 1;
        return 3;
    }

    if (std.mem.eql(u8, op, "mul")) {
        if (instruction.operand_count != 3) return null;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
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
        if (instruction.operand_count == 2) return null;
        if (instruction.operand_count != 3) return null;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return 4;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
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
        std.mem.eql(u8, op, "sb") or
        std.mem.eql(u8, op, "sh") or
        std.mem.eql(u8, op, "sw") or
        std.mem.eql(u8, op, "sc") or
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
        if (instruction.operand_count < 2) return null;
        return estimate_memory_operand_word_count(instruction_operand(instruction, 1));
    }

    if (std.mem.eql(u8, op, "add") or
        std.mem.eql(u8, op, "addu") or
        std.mem.eql(u8, op, "sub") or
        std.mem.eql(u8, op, "subu"))
    {
        if (instruction.operand_count != 3) return null;
        if (operand_parse.parse_register(instruction_operand(instruction, 2)) != null) return null;
        const imm = operand_parse.parse_immediate(instruction_operand(instruction, 2)) orelse return null;
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

    return null; // basic instruction (not a pseudo-op)
}

/// Returns true if the given op is a pseudo-op handled only in count mode
/// (not yet expanded at parse time). Used by process_pseudo_op to distinguish
/// "not a pseudo-op" from "pseudo-op we can't expand yet".
fn is_count_only_pseudo_op(op: []const u8) bool {
    const count_only_ops = [_][]const u8{
        "la",   "blt",  "bltu", "bge",    "bgeu",   "bgt",  "bgtu", "ble",
        "bleu", "abs",  "subi", "subiu",  "neg",    "negu", "mulo", "mulou",
        "div",  "divu", "rem",  "remu",   "ulw",    "usw",  "ulh",  "ulhu",
        "ush",  "rol",  "ror",  "mfc1.d", "mtc1.d", "mulu",
    };
    for (count_only_ops) |pseudo_op| {
        if (std.mem.eql(u8, op, pseudo_op)) return true;
    }
    // Also check ops that are pseudo-ops only with certain operand forms.
    // These are basic instructions with register operands but pseudo-ops with immediates.
    const conditional_pseudo_ops = [_][]const u8{
        "addi", "addiu", "andi", "ori",  "xori", "beq",  "bne",
        "add",  "addu",  "sub",  "subu", "mul",  "seq",  "sge",
        "sgeu", "sle",   "sleu", "sne",  "sgt",  "sgtu", "lb",
        "lbu",  "lh",    "lhu",  "lw",   "ll",   "ld",   "sb",
        "sh",   "sw",    "sc",   "sd",   "lwl",  "lwr",  "swl",
        "swr",  "l.s",   "l.d",  "s.s",  "s.d",  "lwc1", "ldc1",
        "swc1", "sdc1",
    };
    for (conditional_pseudo_ops) |pseudo_op| {
        if (std.mem.eql(u8, op, pseudo_op)) return true;
    }
    return false;
}

/// Try to expand a pseudo-op into basic instructions.
/// Returns true if expanded (caller should NOT store the pseudo-op).
/// Returns false if not a pseudo-op (caller should store as-is).
/// Delegates to process_pseudo_op which is the single source of truth.
fn try_expand_pseudo_op(parsed: *Program, instruction: *const LineInstruction) bool {
    return process_pseudo_op(parsed, instruction, true) != null;
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
    // Delegates to the single source of truth: process_pseudo_op in count mode.
    // Returns the pseudo-op word count, or 1 for basic instructions.
    return process_pseudo_op(null, instruction, false) orelse 1;
}

pub fn estimate_la_word_count(address_operand_text: []const u8) u32 {
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

pub fn estimate_memory_operand_word_count(address_operand_text: []const u8) u32 {
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
        write_reg(state, reg_at, imm);
        return;
    }
    load_at_high_bits_only(state, imm);
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
    // ===================================================================
    // MAIN EXECUTION LOOP: Runs program to completion or error
    // ===================================================================
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

const instructions = @import("instructions/instructions.zig");

fn execute_instruction(
    parsed: *Program,
    state: *ExecState,
    instruction: *const LineInstruction,
    output: []u8,
    output_len_bytes: *u32,
) StatusCode {
    const op = instruction.op[0..instruction.op_len];

    // Dispatch to extracted instruction modules.
    if (instructions.execute(parsed, state, instruction, op)) |status| {
        return status;
    }

    // Syscall and nop remain here since syscall needs output buffers.
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
    return syscall_dispatch.execute(parsed, state, output, output_len_bytes);
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

