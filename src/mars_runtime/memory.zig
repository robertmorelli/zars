// Memory operations for the MIPS runtime.
// This module handles read/write operations for data, heap, and text segments.

const types = @import("types.zig");
const Program = types.Program;
const ExecState = types.ExecState;
const data_base_addr = types.data_base_addr;
const heap_base_addr = types.heap_base_addr;
const text_base_addr = types.text_base_addr;
const heap_capacity_bytes = types.heap_capacity_bytes;

/// Convert data segment address to offset in data array.
pub fn data_address_to_offset(parsed: *Program, address: u32) ?u32 {
    if (address < data_base_addr) return null;
    const offset = address - data_base_addr;
    if (offset >= parsed.data_len_bytes) return null;
    return offset;
}

/// Convert heap address to offset in heap array.
pub fn heap_address_to_offset(state: *ExecState, address: u32) ?u32 {
    if (address < heap_base_addr) return null;
    const offset = address - heap_base_addr;
    if (offset >= state.heap_len_bytes) return null;
    return offset;
}

/// Read single byte from data or heap memory.
pub fn read_u8(parsed: *Program, state: *ExecState, address: u32) ?u8 {
    if (data_address_to_offset(parsed, address)) |offset| {
        return parsed.data[offset];
    }
    if (heap_address_to_offset(state, address)) |offset| {
        return state.heap[offset];
    }
    return null;
}

/// Read 16-bit value big-endian from memory.
pub fn read_u16_be(parsed: *Program, state: *ExecState, address: u32) ?u16 {
    const b0 = read_u8(parsed, state, address) orelse return null;
    const b1 = read_u8(parsed, state, address + 1) orelse return null;
    return @as(u16, b0) | (@as(u16, b1) << 8);
}

/// Read 32-bit value big-endian from memory.
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

/// Read 64-bit value big-endian from memory.
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

/// Write single byte to data or heap memory.
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

/// Write 16-bit value big-endian to memory.
pub fn write_u16_be(parsed: *Program, state: *ExecState, address: u32, value: u16) bool {
    return write_u8(parsed, state, address, @intCast(value & 0xFF)) and
        write_u8(parsed, state, address + 1, @intCast((value >> 8) & 0xFF));
}

/// Write 32-bit value big-endian to memory or text segment (SMC).
pub fn write_u32(parsed: *Program, state: *ExecState, address: u32, value: u32) bool {
    if (write_u32_be(parsed, state, address, value)) return true;
    return write_text_patch_word(parsed, state, address, value);
}

/// Write 32-bit value big-endian to data or heap memory only.
fn write_u32_be(parsed: *Program, state: *ExecState, address: u32, value: u32) bool {
    return write_u8(parsed, state, address, @intCast(value & 0xFF)) and
        write_u8(parsed, state, address + 1, @intCast((value >> 8) & 0xFF)) and
        write_u8(parsed, state, address + 2, @intCast((value >> 16) & 0xFF)) and
        write_u8(parsed, state, address + 3, @intCast((value >> 24) & 0xFF));
}

/// Write patched instruction word to text segment (SMC mode only).
fn write_text_patch_word(parsed: *Program, state: *ExecState, address: u32, value: u32) bool {
    if (!state.smc_enabled) return false;
    const instruction_index = text_address_to_instruction_index(parsed, address) orelse return false;
    state.text_patch_words[instruction_index] = value;
    state.text_patch_valid[instruction_index] = true;
    return true;
}

/// Map text address to instruction index via expansion table.
pub fn text_address_to_instruction_index(parsed: *Program, address: u32) ?u32 {
    if (address < text_base_addr) return null;
    const relative = address - text_base_addr;
    if ((relative & 3) != 0) return null;
    const word_index = relative / 4;
    if (word_index >= parsed.text_word_count) return null;
    if (!parsed.text_word_to_instruction_valid[word_index]) return null;
    return parsed.text_word_to_instruction_index[word_index];
}

/// Map instruction index to text address.
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

/// Allocate heap memory (sbrk syscall). Returns base address of allocation.
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
