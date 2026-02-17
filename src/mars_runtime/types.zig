// Shared types and constants for the MIPS runtime engine pipeline.
// This module defines the core data structures used across all pipeline stages.

const std = @import("std");
const assert = std.debug.assert;

// Re-export types from model and engine_data for convenience.
pub const model = @import("model.zig");
pub const engine_data = @import("engine_data.zig");

pub const Program = model.Program;
pub const LineInstruction = model.LineInstruction;
pub const Label = model.Label;
pub const Fixup = model.Fixup;

// Memory map constants matching MARS layout.
pub const text_base_addr: u32 = 0x00400000;
pub const data_base_addr: u32 = 0x10000000;
pub const heap_base_addr: u32 = 0x10040000;
pub const heap_capacity_bytes: u32 = 16 * 1024 * 1024;

// Capacity limits for runtime structures.
pub const max_instruction_count: u32 = 16 * 1024;
pub const max_label_count: u32 = 1024;
pub const max_fixup_count: u32 = 2048;
pub const max_open_file_count: u32 = 16;
pub const max_virtual_file_count: u32 = 16;
pub const max_random_stream_count: u32 = 8;
pub const virtual_file_name_capacity_bytes: u32 = 256;
pub const virtual_file_data_capacity_bytes: u32 = 64 * 1024;

// Register and instruction constants.
pub const register_count: u32 = 32;
pub const fp_register_count: u32 = 32;
pub const cp0_register_count: u32 = 32;
pub const condition_flag_count: u3 = 8;
pub const mask_shift_amount: u32 = 0x1F;
pub const mask_u32: i64 = 0xFFFF_FFFF;
pub const bits_per_word: u6 = 32;
pub const reg_at: u5 = 1;

/// Status codes returned by runtime operations.
pub const StatusCode = enum {
    ok,
    parse_error,
    runtime_error,
    needs_input,
};

/// Delayed branch state machine.
pub const DelayedBranchState = enum {
    cleared,
    registered,
    triggered,
};

/// Execution state for the MIPS runtime.
pub const ExecState = struct {
    regs: [register_count]i32,
    fp_regs: [fp_register_count]u32,
    cp0_regs: [cp0_register_count]i32,
    hi: i32,
    lo: i32,
    pc: u32,
    halted: bool,
    fp_condition_flags: u8,
    delayed_branching_enabled: bool,
    delayed_branch_state: DelayedBranchState,
    delayed_branch_target: u32,
    smc_enabled: bool,
    input_text: []const u8,
    input_offset_bytes: u32,
    text_patch_words: [max_instruction_count]u32,
    text_patch_valid: [max_instruction_count]bool,
    heap: [heap_capacity_bytes]u8,
    heap_len_bytes: u32,
    open_files: [max_open_file_count]OpenFile,
    virtual_files: [max_virtual_file_count]VirtualFile,
    random_streams: [max_random_stream_count]JavaRandomState,
};

/// Virtual file entry for in-memory file system emulation.
pub const VirtualFile = struct {
    name: [virtual_file_name_capacity_bytes]u8,
    name_len_bytes: u32,
    data: [virtual_file_data_capacity_bytes]u8,
    len_bytes: u32,
    in_use: bool,
};

/// Open file descriptor tracking.
pub const OpenFile = struct {
    file_index: u32,
    position_bytes: u32,
    flags: i32,
    in_use: bool,
};

/// Java-compatible random number generator state.
pub const JavaRandomState = struct {
    initialized: bool,
    stream_id: u32,
    seed: i64,
};

/// RunOptions configure the execution environment.
pub const RunOptions = struct {
    delayed_branching_enabled: bool,
    smc_enabled: bool,
    input_text: []const u8,
};

/// RunResult contains the outcome of program execution.
pub const RunResult = struct {
    status: StatusCode,
    output_len_bytes: u32,
};

/// AddressExpression represents different forms of address operands.
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

/// AddressOperand combines base register and expression.
pub const AddressOperand = struct {
    base_register: ?u5,
    expression: AddressExpression,
};

/// OpenFileMode for file creation.
pub const OpenFileMode = enum {
    truncate,
    append,
};
