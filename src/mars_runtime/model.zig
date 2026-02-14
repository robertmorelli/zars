// Runtime model shared across parser/executor/syscall modules.
// This keeps one authoritative source for all state layout and hard limits.

pub const max_instruction_count: u32 = 4096;
pub const max_label_count: u32 = 1024;
pub const max_token_len: u32 = 64;
pub const data_capacity_bytes: u32 = 64 * 1024;
pub const max_text_word_count: u32 = max_instruction_count * 4;
pub const text_base_addr: u32 = 0x00400000;
pub const data_base_addr: u32 = 0x10010000;
pub const heap_base_addr: u32 = 0x10040000;
pub const heap_capacity_bytes: u32 = 256 * 1024;

pub const max_open_file_count: u32 = 16;
pub const max_virtual_file_count: u32 = 16;
pub const virtual_file_name_capacity_bytes: u32 = 256;
pub const virtual_file_data_capacity_bytes: u32 = 64 * 1024;
pub const max_random_stream_count: u32 = 16;

pub const StatusCode = enum(u32) {
    ok = 0,
    parse_error = 1,
    runtime_error = 3,
};

pub const Label = struct {
    name: [max_token_len]u8,
    len: u8,
    instruction_index: u32,
};

pub const LineInstruction = struct {
    op: [max_token_len]u8,
    op_len: u8,
    operands: [3][max_token_len]u8,
    operand_lens: [3]u8,
    operand_count: u8,
};

pub const Program = struct {
    // Source-level instruction stream.
    instructions: [max_instruction_count]LineInstruction,
    instruction_count: u32,
    // Mapping between source instructions and assembled text word addresses.
    instruction_word_indices: [max_instruction_count]u32,
    text_word_count: u32,
    text_word_to_instruction_index: [max_text_word_count]u32,
    text_word_to_instruction_valid: [max_text_word_count]bool,
    // Label tables for text and data sections.
    labels: [max_label_count]Label,
    label_count: u32,
    data: [data_capacity_bytes]u8,
    data_len_bytes: u32,
    data_labels: [max_label_count]Label,
    data_label_count: u32,
};

pub const VirtualFile = struct {
    name: [virtual_file_name_capacity_bytes]u8,
    name_len_bytes: u32,
    data: [virtual_file_data_capacity_bytes]u8,
    len_bytes: u32,
    in_use: bool,
};

pub const OpenFile = struct {
    file_index: u32,
    position_bytes: u32,
    flags: i32,
    in_use: bool,
};

pub const JavaRandomState = struct {
    initialized: bool,
    stream_id: i32,
    seed: u64,
};

pub const DelayedBranchState = enum(u2) {
    cleared,
    registered,
    triggered,
};

pub const ExecState = struct {
    // Integer and floating-point architectural state.
    regs: [32]i32,
    fp_regs: [32]u32,
    fp_condition_flags: u8,
    cp0_regs: [32]i32,
    hi: i32,
    lo: i32,
    // Program counter is a source instruction index, not a byte address.
    pc: u32,
    halted: bool,
    // Runtime mode flags wired from engine options.
    delayed_branching_enabled: bool,
    smc_enabled: bool,
    // Delayed branch state machine mirrors MARS DelayedBranch behavior.
    delayed_branch_state: DelayedBranchState,
    delayed_branch_target: u32,
    // stdin cursor for syscall input services.
    input_text: []const u8,
    input_offset_bytes: u32,
    // Optional patched words for self-modifying code writes into the text segment.
    text_patch_words: [max_instruction_count]u32,
    text_patch_valid: [max_instruction_count]bool,
    // Heap backing for syscall 9 (sbrk).
    heap: [heap_capacity_bytes]u8,
    heap_len_bytes: u32,
    // In-memory virtual filesystem for syscall 13/14/15/16.
    open_files: [max_open_file_count]OpenFile,
    virtual_files: [max_virtual_file_count]VirtualFile,
    // Java Random stream table for syscall 40-44.
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
