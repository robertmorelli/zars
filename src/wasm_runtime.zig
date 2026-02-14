const runtime = @import("mars_runtime/runtime_state.zig");
const engine = @import("mars_runtime/engine.zig");
const model = @import("mars_runtime/model.zig");

comptime {
    // The exported pointers are u32 offsets into wasm linear memory.
    if (@sizeOf(usize) != 4) {
        @compileError("WASM runtime expects 32-bit pointers.");
    }
}

pub export fn zars_reset() void {
    runtime.runtime_state.reset();
}

pub export fn zars_program_ptr() u32 {
    // Host writes source bytes directly into this buffer.
    return @intCast(@intFromPtr(&runtime.program_storage[0]));
}

pub export fn zars_program_capacity_bytes() u32 {
    return runtime.program_capacity_bytes;
}

pub export fn zars_output_ptr() u32 {
    // Host reads runtime stdout bytes from this buffer after `zars_run`.
    return @intCast(@intFromPtr(&runtime.output_storage[0]));
}

pub export fn zars_output_len_bytes() u32 {
    return runtime.runtime_state.output_len_bytes;
}

pub export fn zars_output_capacity_bytes() u32 {
    return runtime.output_capacity_bytes;
}

pub export fn zars_input_ptr() u32 {
    // Host writes stdin bytes into this buffer before `zars_set_input_len_bytes`.
    return @intCast(@intFromPtr(&runtime.input_storage[0]));
}

pub export fn zars_input_capacity_bytes() u32 {
    return runtime.input_capacity_bytes;
}

pub export fn zars_last_status_code() u32 {
    return @intFromEnum(runtime.runtime_state.last_status_code);
}

pub export fn zars_regs_ptr() u32 {
    return @intCast(@intFromPtr(&engine.snapshot_regs()[0]));
}

pub export fn zars_fp_regs_ptr() u32 {
    return @intCast(@intFromPtr(&engine.snapshot_fp_regs()[0]));
}

pub export fn zars_data_ptr() u32 {
    return @intCast(@intFromPtr(&engine.snapshot_data_bytes()[0]));
}

pub export fn zars_data_len_bytes() u32 {
    return engine.snapshot_data_len_bytes();
}

pub export fn zars_heap_ptr() u32 {
    return @intCast(@intFromPtr(&engine.snapshot_heap_bytes()[0]));
}

pub export fn zars_heap_len_bytes() u32 {
    return engine.snapshot_heap_len_bytes();
}

pub export fn zars_data_base_addr() u32 {
    return model.data_base_addr;
}

pub export fn zars_heap_base_addr() u32 {
    return model.heap_base_addr;
}

pub export fn zars_load_program(program_len_bytes: u32) u32 {
    const status = runtime.runtime_state.load_program(program_len_bytes);
    return @intFromEnum(status);
}

pub export fn zars_set_delayed_branching(enabled: u32) void {
    runtime.runtime_state.set_delayed_branching(enabled != 0);
}

pub export fn zars_set_smc_enabled(enabled: u32) void {
    runtime.runtime_state.set_smc(enabled != 0);
}

pub export fn zars_set_input_len_bytes(len_bytes: u32) u32 {
    // Declares how many bytes in `input_storage` are valid for this run.
    const status = runtime.runtime_state.set_input_len(len_bytes);
    return @intFromEnum(status);
}

pub export fn zars_run() u32 {
    const status = runtime.runtime_state.run();
    return @intFromEnum(status);
}
