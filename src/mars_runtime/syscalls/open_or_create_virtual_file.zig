const model = @import("model.zig");

const ExecState = model.ExecState;

const max_virtual_file_count = model.max_virtual_file_count;
const virtual_file_name_capacity_bytes = model.virtual_file_name_capacity_bytes;

pub const OpenFileMode = enum {
    truncate,
    append,
};

pub fn open_or_create_virtual_file(state: *ExecState, name: []const u8, mode: OpenFileMode) ?u32 {
    // Imported from engine.zig to access find_virtual_file_by_name
    // For now, include the lookup inline
    var i: u32 = 0;
    while (i < max_virtual_file_count) : (i += 1) {
        const file = &state.virtual_files[i];
        if (!file.in_use) continue;
        const existing_name = file.name[0..file.name_len_bytes];
        if (std.mem.eql(u8, existing_name, name)) {
            if (mode == .truncate) {
                file.len_bytes = 0;
            }
            return i;
        }
    }

    i = 0;
    while (i < max_virtual_file_count) : (i += 1) {
        const file = &state.virtual_files[i];
        if (file.in_use) continue;
        if (name.len > virtual_file_name_capacity_bytes) return null;
        @memset(file.name[0..], 0);
        @import("std").mem.copyForwards(u8, file.name[0..name.len], name);
        file.name_len_bytes = @intCast(name.len);
        file.len_bytes = 0;
        file.in_use = true;
        @memset(file.data[0..], 0);
        return i;
    }

    return null;
}
