const std = @import("std");
const globals = @import("globals.zig");
const engine = @import("engine.zig");

pub const StatusCode = enum(u32) {
    ok = 0,
    invalid_program_length = 1,
    program_not_loaded = 2,
    parse_error = 3,
    halted = 4,
    runtime_error = 5,
    needs_input = 6,
};

pub const program_capacity_bytes: u32 = 1024 * 1024;
pub const output_capacity_bytes: u32 = 1024 * 1024;
pub const input_capacity_bytes: u32 = 64 * 1024;

// Runtime buffers are static so wasm host code can write/read by pointer.
pub var program_storage: [program_capacity_bytes]u8 = [_]u8{0} ** program_capacity_bytes;
pub var output_storage: [output_capacity_bytes]u8 = [_]u8{0} ** output_capacity_bytes;
pub var input_storage: [input_capacity_bytes]u8 = [_]u8{0} ** input_capacity_bytes;

pub const RuntimeState = struct {
    loaded_program_len_bytes: u32 = 0,
    output_len_bytes: u32 = 0,
    last_status_code: StatusCode = .ok,
    delayed_branching_enabled: bool = false,
    smc_enabled: bool = false,
    input_len_bytes: u32 = 0,
    /// Watermark for incremental output reads. Tracks how far the host has read.
    output_read_offset_bytes: u32 = 0,

    pub fn reset(self: *RuntimeState) void {
        // Reset both metadata and backing buffers between runs.
        self.loaded_program_len_bytes = 0;
        self.output_len_bytes = 0;
        self.last_status_code = .ok;
        self.delayed_branching_enabled = false;
        self.smc_enabled = false;
        self.input_len_bytes = 0;
        self.output_read_offset_bytes = 0;
        @memset(program_storage[0..], 0);
        @memset(output_storage[0..], 0);
        @memset(input_storage[0..], 0);
    }

    pub fn load_program(self: *RuntimeState, program_len_bytes: u32) StatusCode {
        // The host writes program bytes into `program_storage`, then registers length here.
        if (program_len_bytes > program_capacity_bytes) {
            self.loaded_program_len_bytes = 0;
            self.last_status_code = .invalid_program_length;
            return self.last_status_code;
        }

        self.loaded_program_len_bytes = program_len_bytes;
        self.last_status_code = .ok;
        return self.last_status_code;
    }

    pub fn run(self: *RuntimeState) StatusCode {
        if (self.loaded_program_len_bytes == 0) {
            self.last_status_code = .program_not_loaded;
            return self.last_status_code;
        }

        // Validate compile-time and runtime invariants before dispatch.
        globals.validate_invariants();

        const program_len: usize = @intCast(self.loaded_program_len_bytes);
        const result = engine.run_program(program_storage[0..program_len], output_storage[0..], .{
            .delayed_branching_enabled = self.delayed_branching_enabled,
            .smc_enabled = self.smc_enabled,
            .input_text = input_storage[0..self.input_len_bytes],
        });
        self.output_len_bytes = result.output_len_bytes;
        self.last_status_code = map_engine_status(result.status);
        return self.last_status_code;
    }

    pub fn set_delayed_branching(self: *RuntimeState, enabled: bool) void {
        self.delayed_branching_enabled = enabled;
    }

    pub fn set_smc(self: *RuntimeState, enabled: bool) void {
        self.smc_enabled = enabled;
    }

    pub fn set_input_len(self: *RuntimeState, len_bytes: u32) StatusCode {
        // Input bytes are written by host to `input_storage`; this call sets active prefix length.
        if (len_bytes > input_capacity_bytes) {
            self.last_status_code = .invalid_program_length;
            return self.last_status_code;
        }
        self.input_len_bytes = len_bytes;
        self.last_status_code = .ok;
        return self.last_status_code;
    }

    /// Initialize execution for step-by-step mode. Call this after load_program.
    pub fn start(self: *RuntimeState) StatusCode {
        if (self.loaded_program_len_bytes == 0) {
            self.last_status_code = .program_not_loaded;
            return self.last_status_code;
        }

        globals.validate_invariants();

        const program_len: usize = @intCast(self.loaded_program_len_bytes);
        const status = engine.init_execution(program_storage[0..program_len], output_storage[0..], .{
            .delayed_branching_enabled = self.delayed_branching_enabled,
            .smc_enabled = self.smc_enabled,
            .input_text = input_storage[0..self.input_len_bytes],
        });
        self.output_len_bytes = 0;
        self.last_status_code = map_engine_status(status);
        return self.last_status_code;
    }

    /// Execute exactly one instruction. Returns status after the step.
    pub fn step(self: *RuntimeState) StatusCode {
        const status = engine.step_execution();
        self.output_len_bytes = engine.step_output_len();
        self.last_status_code = map_engine_status(status);
        return self.last_status_code;
    }

    /// Run at full speed until the program halts, errors, or needs input.
    pub fn run_until_input(self: *RuntimeState) StatusCode {
        const status = engine.run_until_input();
        self.output_len_bytes = engine.step_output_len();
        self.last_status_code = map_engine_status(status);
        return self.last_status_code;
    }

    /// Append input bytes. Host writes new bytes at input_storage[old_len..old_len+additional_len],
    /// then calls this to extend the active input window without resetting the read cursor.
    pub fn append_input(self: *RuntimeState, additional_len: u32) StatusCode {
        const new_total = self.input_len_bytes + additional_len;
        if (new_total > input_capacity_bytes) {
            self.last_status_code = .invalid_program_length;
            return self.last_status_code;
        }
        self.input_len_bytes = new_total;
        // Update the engine's input slice to reflect the new length.
        engine.update_input_slice(input_storage[0..new_total]);
        self.last_status_code = .ok;
        return self.last_status_code;
    }

    /// Returns how many input bytes have been consumed by the program so far.
    pub fn input_consumed_bytes(_: *const RuntimeState) u32 {
        return engine.snapshot_input_offset_bytes();
    }

    /// Returns the number of new output bytes since the last call to this function.
    /// Advances the read watermark.
    pub fn consume_new_output(self: *RuntimeState) u32 {
        const new_bytes = self.output_len_bytes - self.output_read_offset_bytes;
        self.output_read_offset_bytes = self.output_len_bytes;
        return new_bytes;
    }

    /// Returns the byte offset where new (unconsumed) output starts.
    pub fn new_output_offset(self: *const RuntimeState) u32 {
        return self.output_read_offset_bytes;
    }
};

fn map_engine_status(status: engine.StatusCode) StatusCode {
    // External status enum intentionally wraps the engine-specific status enum.
    return switch (status) {
        .ok => .ok,
        .parse_error => .parse_error,
        .runtime_error => .runtime_error,
        .halted => .halted,
        .needs_input => .needs_input,
    };
}

pub var runtime_state: RuntimeState = .{};

test "runtime state requires loaded program" {
    runtime_state.reset();

    const status = runtime_state.run();
    try std.testing.expectEqual(StatusCode.program_not_loaded, status);
}
