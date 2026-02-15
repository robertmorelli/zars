  Priority 1: State Inspection (quick wins)

  // Export these from ExecState:
  pub export fn zars_hi() i32
  pub export fn zars_lo() i32
  pub export fn zars_pc() u32
  pub export fn zars_halted() u32
  pub export fn zars_fp_condition_flags() u8

  Priority 2: Step Execution (enables DAP + interactive input)

  // Execute exactly one instruction, return status
  pub export fn zars_step() u32

  // Status codes (extend existing enum)
  pub const StatusCode = enum(u32) {
      ok = 0,
      parse_error = 1,
      program_not_loaded = 2,
      runtime_error = 3,
      halted = 4,           // NEW: program exited normally
      needs_input = 5,      // NEW: syscall waiting for input
      breakpoint_hit = 6,   // NEW: hit a breakpoint
  };

  Priority 3: Breakpoints

  pub export fn zars_set_breakpoint(pc: u32) void
  pub export fn zars_clear_breakpoint(pc: u32) void
  pub export fn zars_clear_all_breakpoints() void

  // Internal: array of breakpoint PCs
  var breakpoints: [64]u32 = undefined;
  var breakpoint_count: u32 = 0;

  Priority 4: Source Mapping

  // Map PC (instruction index) to source line number
  pub export fn zars_pc_to_source_line(pc: u32) u32

  // Map source line to PC (for setting breakpoints by line)
  pub export fn zars_source_line_to_pc(line: u32) u32

  // Get instruction count (for bounds checking)
  pub export fn zars_instruction_count() u32

  Priority 5: Error Details

  // When parse_error or runtime_error, get details:
  pub export fn zars_error_line() u32           // Which line failed
  pub export fn zars_error_message_ptr() u32    // Error string
  pub export fn zars_error_message_len() u32

  Priority 6: Text Segment Access (for disassembly view)

  pub export fn zars_text_ptr() u32             // Assembled machine code
  pub export fn zars_text_len_bytes() u32
  pub export fn zars_text_base_addr() u32       // 0x00400000

  ---
  Summary Table
  ┌──────────────────────────┬───────────────────────┬──────────┐
  │          Export          │        Purpose        │ Priority │
  ├──────────────────────────┼───────────────────────┼──────────┤
  │ zars_hi/lo/pc/halted     │ Show full CPU state   │ P1       │
  ├──────────────────────────┼───────────────────────┼──────────┤
  │ zars_step()              │ Single-step execution │ P2       │
  ├──────────────────────────┼───────────────────────┼──────────┤
  │ needs_input status       │ Interactive I/O       │ P2       │
  ├──────────────────────────┼───────────────────────┼──────────┤
  │ zars_set_breakpoint()    │ Debugging             │ P3       │
  ├──────────────────────────┼───────────────────────┼──────────┤
  │ zars_pc_to_source_line() │ Source mapping        │ P4       │
  ├──────────────────────────┼───────────────────────┼──────────┤
  │ zars_error_line/message  │ Better error UX       │ P5       │
  ├──────────────────────────┼───────────────────────┼──────────┤
  │ zars_text_ptr()          │ Disassembly view      │ P6       │
  └──────────────────────────┴───────────────────────┴──────────┘
  ---
  P1 + P2 unlocks the simulator view with interactive input.
  P1 + P2 + P3 + P4 unlocks full DAP debugging.
