// Syscall module - Central import point for all syscall-related functions
pub const sbrk = @import("syscall_sbrk.zig");
pub const file_ops = @import("syscall_open_file.zig");
pub const dialog = @import("syscall_dialog.zig");
pub const time_audio = @import("time_and_audio.zig");
pub const input = @import("input_readers.zig");
pub const virtual_files = struct {
    pub const find_by_name = @import("find_virtual_file_by_name.zig").find_virtual_file_by_name;
    pub const open_or_create = @import("open_or_create_virtual_file.zig").open_or_create_virtual_file;
};

// Re-exports for convenience
pub const syscall_sbrk = sbrk.syscall_sbrk;
pub const syscall_headless_dialog_termination = dialog.syscall_headless_dialog_termination;
pub const sanitize_midi_parameter = time_audio.sanitize_midi_parameter;
pub const sanitize_midi_duration = time_audio.sanitize_midi_duration;
pub const current_time_millis_bits = time_audio.current_time_millis_bits;
