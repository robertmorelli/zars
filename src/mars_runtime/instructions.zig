// Instructions module - Central import point for instruction-related functions
// Note: Most instruction logic is currently in execute_instruction() switch statement in engine.zig
// This module organizes helper functions used during instruction execution

pub const bitwise = @import("instructions/bitwise_ops.zig");
