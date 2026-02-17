// Register access and management for the MIPS runtime.
// This module provides helpers for integer registers, floating-point registers,
// HI/LO registers, and FP condition flags.

const types = @import("types.zig");
const ExecState = types.ExecState;

/// Read integer register value. Register $zero always returns 0.
pub fn read_reg(state: *ExecState, reg: u5) i32 {
    return state.regs[reg];
}

/// Write integer register value. Writes to $zero are ignored.
pub fn write_reg(state: *ExecState, reg: u5, value: i32) void {
    if (reg == 0) return;
    state.regs[reg] = value;
}

/// Read single-precision floating-point register bits.
pub fn read_fp_single(state: *ExecState, reg: u5) u32 {
    return state.fp_regs[reg];
}

/// Write single-precision floating-point register bits.
pub fn write_fp_single(state: *ExecState, reg: u5, bits: u32) void {
    state.fp_regs[reg] = bits;
}

/// Read double-precision floating-point register pair bits.
/// Reads from reg and reg+1 (low word first, then high word).
pub fn read_fp_double(state: *ExecState, reg: u5) u64 {
    const low_word = @as(u64, state.fp_regs[reg]);
    const high_word = @as(u64, state.fp_regs[reg + 1]);
    return (high_word << 32) | low_word;
}

/// Write double-precision floating-point register pair bits.
/// Writes to reg and reg+1 (low word first, then high word).
pub fn write_fp_double(state: *ExecState, reg: u5, bits: u64) void {
    state.fp_regs[reg] = @intCast(bits & 0xFFFF_FFFF);
    state.fp_regs[reg + 1] = @intCast((bits >> 32) & 0xFFFF_FFFF);
}

/// Check if a register number is valid for double-precision FP operations.
/// Must be even and less than 31.
pub fn fp_double_register_pair_valid(reg: u5) bool {
    if ((reg & 1) != 0) return false;
    return reg < 31;
}

/// Set floating-point condition flag.
pub fn set_fp_condition_flag(state: *ExecState, flag: u3, enabled: bool) void {
    const mask: u8 = @as(u8, 1) << flag;
    if (enabled) {
        state.fp_condition_flags |= mask;
    } else {
        state.fp_condition_flags &= ~mask;
    }
}

/// Get floating-point condition flag state.
pub fn get_fp_condition_flag(state: *ExecState, flag: u3) bool {
    const mask: u8 = @as(u8, 1) << flag;
    return (state.fp_condition_flags & mask) != 0;
}
