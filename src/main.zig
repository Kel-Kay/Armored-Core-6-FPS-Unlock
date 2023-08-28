const std = @import("std");
const win = @import("win32_import.zig");
const tools = @import("tools.zig");

const proc_names = [_][*:0]const u16{
    win.L("armoredcore6.exe"),
    win.L("start_protected_game.exe"),
};

const fps_pattern = [_]?u8{ 0x89, 0x88, 0x08, 0x3C, 0xEB, null, 0xC7, 0x43, null, 0x89, 0x88, 0x08, 0x3C };

const fps_pattern_offset = 9;

const new_cap = 360.0;
const new_frametime: f32 = 1.0 / new_cap;

pub fn main() !void {
    const exe_name = try tools.getExecutableName(std.heap.c_allocator);
    defer std.heap.c_allocator.free(exe_name);

    //if the executable is called start_protected_game it is expected to do exactly that
    const is_starter = tools.stringEql(@ptrCast(exe_name.ptr), proc_names[1]);
    if (is_starter) {
        if (tools.fileExists(proc_names[0])) {
            var proc_info: win.PROCESS_INFORMATION = undefined;
            var startup_info: win.STARTUPINFOW = undefined;

            _ = win.GetStartupInfoW(&startup_info);

            const proc_creation = win.CreateProcessW(proc_names[0], win.GetCommandLineW(), null, null, win.FALSE, 0, null, null, &startup_info, &proc_info);

            if (proc_creation == win.FALSE) return error.FailedToStartProcess;

            _ = win.CloseHandle(proc_info.hProcess);
            _ = win.CloseHandle(proc_info.hThread);

            _ = win.Sleep(5000);
        }
    }

    var proc_handle: *anyopaque = undefined;
    var mod_name: [*:0]const u16 = undefined;

    if (is_starter) {
        proc_handle = try tools.findProcess(proc_names[0]);
        mod_name = proc_names[0];
    } else {
        proc_handle = try tools.findProcess(proc_names[1]);
        mod_name = proc_names[1];
    }

    defer _ = win.CloseHandle(proc_handle);

    const mod_handle = try tools.findModule(proc_handle, mod_name);
    const mod_size = try tools.getModuleSize(proc_handle, mod_handle);
    const mod_copy = win.VirtualAlloc(null, mod_size, win.MEM_COMMIT | win.MEM_RESERVE, win.PAGE_READWRITE) orelse return error.FailedToCopyModule;
    defer _ = win.VirtualFree(mod_copy, 0, win.MEM_RELEASE);

    _ = win.ReadProcessMemory(proc_handle, mod_handle, mod_copy, mod_size, null);

    const fps_pattern_ptr = try tools.findPattern(&fps_pattern, mod_copy, mod_size);
    const fps_pattern_rel = @intFromPtr(fps_pattern_ptr) - @intFromPtr(mod_copy);

    var success = win.TRUE;
    success *= win.WriteProcessMemory(proc_handle, @ptrFromInt(@intFromPtr(mod_handle) + fps_pattern_rel), &new_frametime, @sizeOf(f32), null);
    success *= win.WriteProcessMemory(proc_handle, @ptrFromInt(@intFromPtr(mod_handle) + fps_pattern_rel + fps_pattern_offset), &new_frametime, @sizeOf(f32), null);

    return if (success == win.FALSE) error.FailedToWriteProcessMemory;
}
