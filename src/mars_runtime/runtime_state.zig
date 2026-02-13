const std = @import("std");
const globals = @import("globals.zig");
const engine = @import("engine.zig");

pub const StatusCode = enum(u32) {
    ok = 0,
    invalid_program_length = 1,
    program_not_loaded = 2,
    parse_error = 3,
    unsupported_instruction = 4,
    runtime_error = 5,
};

pub const program_capacity_bytes: u32 = 1024 * 1024;
pub const output_capacity_bytes: u32 = 1024 * 1024;
pub const input_capacity_bytes: u32 = 64 * 1024;

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

    pub fn reset(self: *RuntimeState) void {
        self.loaded_program_len_bytes = 0;
        self.output_len_bytes = 0;
        self.last_status_code = .ok;
        self.delayed_branching_enabled = false;
        self.smc_enabled = false;
        self.input_len_bytes = 0;
        @memset(program_storage[0..], 0);
        @memset(output_storage[0..], 0);
        @memset(input_storage[0..], 0);
    }

    pub fn load_program(self: *RuntimeState, program_len_bytes: u32) StatusCode {
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
        if (len_bytes > input_capacity_bytes) {
            self.last_status_code = .invalid_program_length;
            return self.last_status_code;
        }
        self.input_len_bytes = len_bytes;
        self.last_status_code = .ok;
        return self.last_status_code;
    }
};

fn map_engine_status(status: engine.StatusCode) StatusCode {
    return switch (status) {
        .ok => .ok,
        .parse_error => .parse_error,
        .unsupported_instruction => .unsupported_instruction,
        .runtime_error => .runtime_error,
    };
}

pub var runtime_state: RuntimeState = .{};

test "runtime state requires loaded program" {
    runtime_state.reset();

    const status = runtime_state.run();
    try std.testing.expectEqual(StatusCode.program_not_loaded, status);
}
