const model = @import("model.zig");
const ExecState = model.ExecState;

const heap_base_addr = model.heap_base_addr;
const heap_capacity_bytes = model.heap_capacity_bytes;

pub fn syscall_sbrk(state: *ExecState, allocation_size: i32) ?u32 {
    // MARS keeps heap word-aligned after each allocation.
    if (allocation_size < 0) return null;
    const old_len = state.heap_len_bytes;
    var new_len = old_len + @as(u32, @intCast(allocation_size));
    if ((new_len & 3) != 0) {
        new_len += 4 - (new_len & 3);
    }
    if (new_len > heap_capacity_bytes) return null;
    state.heap_len_bytes = new_len;
    return heap_base_addr + old_len;
}
