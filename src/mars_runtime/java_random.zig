const std = @import("std");
const assert = std.debug.assert;
const model = @import("model.zig");

const ExecState = model.ExecState;
const JavaRandomState = model.JavaRandomState;
const max_random_stream_count = model.max_random_stream_count;

pub fn set_random_seed(state: *ExecState, stream_id: i32, seed: i32) ?void {
    const random_state = ensure_random_stream(state, stream_id) orelse return null;
    java_random_set_seed(random_state, seed);
}

pub fn next_int(state: *ExecState, stream_id: i32) ?i32 {
    const random_state = ensure_random_stream(state, stream_id) orelse return null;
    return @bitCast(java_random_next_bits(random_state, 32));
}

pub fn next_int_bound(state: *ExecState, stream_id: i32, bound: i32) ?i32 {
    // Mirrors java.util.Random nextInt(bound) fast path + rejection sampling.
    if (bound <= 0) return null;
    const random_state = ensure_random_stream(state, stream_id) orelse return null;
    if ((bound & -bound) == bound) {
        const value = (@as(i64, bound) * @as(i64, @intCast(java_random_next_bits(random_state, 31)))) >> 31;
        return @intCast(value);
    }

    const bound_i64: i64 = bound;
    while (true) {
        const bits_i64: i64 = @intCast(java_random_next_bits(random_state, 31));
        const value_i64 = @mod(bits_i64, bound_i64);
        if (bits_i64 - value_i64 + (bound_i64 - 1) >= 0) {
            return @intCast(value_i64);
        }
    }
}

pub fn next_float(state: *ExecState, stream_id: i32) ?f32 {
    const random_state = ensure_random_stream(state, stream_id) orelse return null;
    const numerator = java_random_next_bits(random_state, 24);
    return @as(f32, @floatFromInt(numerator)) / 16777216.0;
}

pub fn next_double(state: *ExecState, stream_id: i32) ?f64 {
    const random_state = ensure_random_stream(state, stream_id) orelse return null;
    const high = @as(u64, java_random_next_bits(random_state, 26));
    const low = @as(u64, java_random_next_bits(random_state, 27));
    const numerator = (high << 27) + low;
    return @as(f64, @floatFromInt(numerator)) / 9007199254740992.0;
}

fn ensure_random_stream(state: *ExecState, stream_id: i32) ?*JavaRandomState {
    // Streams are keyed by stream_id and lazily initialized.
    var i: u32 = 0;
    while (i < max_random_stream_count) : (i += 1) {
        const random_state = &state.random_streams[i];
        if (!random_state.initialized) continue;
        if (random_state.stream_id == stream_id) {
            return random_state;
        }
    }

    i = 0;
    while (i < max_random_stream_count) : (i += 1) {
        const random_state = &state.random_streams[i];
        if (random_state.initialized) continue;
        random_state.initialized = true;
        random_state.stream_id = stream_id;
        java_random_set_seed(random_state, stream_id);
        return random_state;
    }

    return null;
}

fn java_random_set_seed(random_state: *JavaRandomState, seed: i32) void {
    // Java Random uses a 48-bit LCG state.
    const multiplier: u64 = 0x5DEECE66D;
    const mask: u64 = (1 << 48) - 1;
    const seed_signed: i64 = seed;
    const seed_bits: u64 = @bitCast(seed_signed);
    random_state.seed = (seed_bits ^ multiplier) & mask;
}

fn java_random_next_bits(random_state: *JavaRandomState, bits: u8) u32 {
    assert(bits <= 32);
    const multiplier: u64 = 0x5DEECE66D;
    const addend: u64 = 0xB;
    const mask: u64 = (1 << 48) - 1;
    const bits_u6: u6 = @intCast(bits);
    random_state.seed = (random_state.seed *% multiplier +% addend) & mask;
    const shift: u6 = 48 - bits_u6;
    return @intCast(random_state.seed >> shift);
}
