const types = @import("types.zig");

const Program = types.Program;
const LineInstruction = types.LineInstruction;

/// Try to expand a pseudo-op into basic instructions.
/// Returns true if expanded, false if not a pseudo-op.
/// Currently forwards to engine.zig - full extraction TODO.
pub fn try_expand_pseudo_op(parsed: *Program, instruction: *const LineInstruction) bool {
    return process_pseudo_op(parsed, instruction, true) != null;
}

/// Single source of truth for pseudo-op expansion and word count estimation.
/// When emit=true: expands pseudo-ops, returns word count or null.
/// When emit=false: returns word count for pseudo-ops, null for basic instructions.
/// Currently forwards to engine.zig - full extraction TODO (1700+ lines).
pub fn process_pseudo_op(parsed_opt: ?*Program, instruction: *const LineInstruction, emit: bool) ?u32 {
    // TODO: Extract full process_pseudo_op logic from engine.zig
    // This is a 1700-line function covering 50+ pseudo-instructions.
    // For now, this is a stub that will be filled in next iteration.
    _ = parsed_opt;
    _ = instruction;
    _ = emit;
    return null; // Treat all as basic instructions for initial compilation
}
