const std = @import("std");
const model = @import("model.zig");

const ExecState = model.ExecState;

pub fn sanitize_midi_parameter(value: i32, default_value: i32) i32 {
    if (value < 0 or value > 127) return default_value;
    return value;
}

pub fn sanitize_midi_duration(value: i32, default_value: i32) i32 {
    if (value < 0) return default_value;
    return value;
}

pub fn current_time_millis_bits() u64 {
    const builtin = @import("builtin");
    if (builtin.target.cpu.arch == .wasm32) {
        // Freestanding wasm has no wall-clock API in this runtime.
        // A fixed non-zero value preserves testable architectural behavior.
        return 1;
    }
    const millis_i64 = std.time.milliTimestamp();
    return @bitCast(millis_i64);
}
