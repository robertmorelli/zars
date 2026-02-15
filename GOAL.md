# Goals
- create a web assembly runtime for mips assembly using zig
- match MARS behavior exactly by matching logic, line for line where possible. smc is not an edge case
- make a zig lsp using web assembly for mips programs. it should match the info that MARS exposes

# Design Principles

## MARS Parity is Non-Negotiable
We always strive to match MARS. Always. This includes:
- **Instruction expansion**: Pseudo-ops must expand to the exact same machine instruction sequence as MARS (see MARS/PseudoOps.txt)
- **Step-level execution**: Each step in zars should correspond to one machine instruction, matching MARS's step count exactly
- **Register/memory state**: All registers and memory must match MARS at every step, not just at program completion
- **Edge cases**: SMC, delayed branching, syscalls, and all other behaviors must match MARS exactly

When in doubt, check what MARS does and match it.

