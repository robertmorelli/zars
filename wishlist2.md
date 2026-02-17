# Zars Wishlist

This is the Zars-side work needed to make the LSP migration easy in this repo.

## Priority 0: LSP Migration Must-Haves

### Structured Diagnostics Export
```zig
// Number of errors/warnings from last parse/load call
pub export fn zars_diagnostic_count() u32;

// Per-diagnostic accessors (index 0..count-1)
pub export fn zars_diagnostic_line(index: u32) u32;      // 1-based line number
pub export fn zars_diagnostic_column(index: u32) u32;    // 1-based column
pub export fn zars_diagnostic_is_warning(index: u32) u32; // 0=error, 1=warning
pub export fn zars_diagnostic_message_ptr(index: u32) u32;
pub export fn zars_diagnostic_message_len(index: u32) u32;
```

### Error-Tolerant Parsing (Parse-Only Mode)
```zig
// Parse-only mode: collect errors without executing
pub export fn zars_parse_only(len: u32) u32;
```

Behavior: collect all diagnostics (do not abort on first error), assemble/validate, skip simulator memory load.

### Symbol Table Export (Labels)
```zig
// Number of labels defined in the program
pub export fn zars_label_count() u32;

// Per-label accessors
pub export fn zars_label_name_ptr(index: u32) u32;
pub export fn zars_label_name_len(index: u32) u32;
pub export fn zars_label_line(index: u32) u32;     // source line where defined
pub export fn zars_label_address(index: u32) u32;  // resolved address
```

### .include Resolution Strategy
Choose one:
- Zars preprocessor resolves includes; host provides file resolution via WASM import.
- Host (TypeScript) inlines includes before calling Zars.

If Zars handles includes, add a WASM import like:
```zig
extern fn resolve_file(path_ptr: u32, path_len: u32) u32;
```
where the host returns a pointer/length to the file content in shared memory.

### Line/Column Conventions
Diagnostics and label line numbers should be 1-based to match VS Code conventions.

## Tests/Validation Targets

- Feed broken .s files and compare diagnostics against MARS behavior.
- Side-by-side compare diagnostics vs the legacy TS assembler to validate parity.
- Verify labels resolve with correct line numbers and addresses in mixed .text/.data.

## Future Wishlist: Interactive Execution

### New Status Code
```zig
pub const StatusCode = enum(u32) {
    ok = 0,
    invalid_program_length = 1,
    program_not_loaded = 2,
    parse_error = 3,
    halted = 4,
    runtime_error = 5,
    needs_input = 6,  // NEW: read syscall hit, input buffer empty
};
```

### New Export: Run Until Input Needed
```zig
/// Run until: halted, error, or input needed.
/// Much faster than stepping - runs at full speed until pause point.
pub export fn zars_run_until_input() u32 {
    // Execute instructions until:
    // - Program halts (syscall 10/17) -> return .halted
    // - Error occurs -> return .runtime_error
    // - Read syscall (5,6,7,8,12) hit AND input buffer empty -> return .needs_input
    // - Read syscall hit AND input available -> consume input, continue
}
```

### Behavior Change in Read Syscalls
Current: If input buffer empty -> runtime_error
New: If input buffer empty -> needs_input (don't advance PC, let host provide input and retry)

### Input Buffer Management
```zig
/// Append new input to existing buffer (for interactive mode).
/// Returns new total length, or error if overflow.
pub export fn zars_append_input(len: u32) u32 {
    // Host writes to input_ptr + current_input_len
    // This adds to existing input rather than replacing
}

/// Get current input cursor position (how much has been consumed)
pub export fn zars_input_consumed_bytes() u32;
```

### Output Streaming
```zig
/// Get output written since last call to this function.
/// Useful for streaming output to UI in real-time.
pub export fn zars_output_since_last() u32;  // Returns length of new output

/// Get pointer to start of new output (output_ptr + last_checked_len)
pub export fn zars_new_output_ptr() u32;
```
