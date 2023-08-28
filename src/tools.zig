const std = @import("std");
const win = @import("win32_import.zig");

pub const failure = error{
    FailedToCreateSnapshot,
    FailedToFindModule,
    FailedToOpenProcess,
    FailedToRetrieveModuleInfo,
    FailedToFindPattern,
    FailedToFindProcess,
    FailedToCopyModule,
    FailedToStartProcess,
    FailedToFindAndStartProcess,
    FailedToWriteProcessMemory,
};

pub fn fileExists(name: [*:0]const u16) bool {
    var data: win.WIN32_FIND_DATAW = undefined;
    const handle = win.FindFirstFileW(name, &data);

    if (handle != std.os.windows.INVALID_HANDLE_VALUE) {
        _ = win.CloseHandle(handle);
        return true;
    }

    return false;
}

///caller is responsible for freeing allocated memory
pub fn getExecutableName(allocator: std.mem.Allocator) ![]const u16 {
    var buffer = try allocator.alloc(u16, 1024);
    defer allocator.free(buffer);

    const len = win.GetModuleFileNameW(null, buffer.ptr, @truncate(buffer.len));
    if (len == 0) {
        return error.FailedToGetExecutableName;
    }

    var last_char: usize = 0;
    while (buffer[last_char] != 0) {
        last_char += 1;
    }

    //increment to include null terminator
    last_char += 1;

    var first_char: usize = last_char;
    while (buffer[first_char] != 0x5C and first_char > 0) {
        first_char -= 1;
    }

    //increment to exclude backslash (if there is one)
    if (first_char > 0) {
        first_char += 1;
    }

    var name = try allocator.alloc(u16, last_char - first_char);

    var index: usize = 0;
    while (first_char < last_char) {
        name[index] = buffer[first_char];
        first_char += 1;
        index += 1;
    }

    return name;
}

pub fn findProcess(proc_name: [*:0]const u16) failure!*anyopaque {
    const snapshot = win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0);
    if (snapshot == win.INVALID_HANDLE_VALUE) return failure.FailedToCreateSnapshot;
    defer _ = win.CloseHandle(snapshot);

    var proc_entry = std.mem.zeroes(win.PROCESSENTRY32W);
    proc_entry.dwSize = @sizeOf(win.PROCESSENTRY32W);

    var opt_proc_id: ?u32 = null;
    var mod_name: [*:0]const u16 = undefined;

    if (win.Process32FirstW(snapshot, &proc_entry) == win.TRUE) {
        var has_proc = true;
        out: while (has_proc) {
            if (stringEql(@ptrCast(&proc_entry.szExeFile), proc_name)) {
                opt_proc_id = proc_entry.th32ProcessID;
                mod_name = @ptrCast(&proc_entry.szExeFile);
                break :out;
            }

            has_proc = win.Process32NextW(snapshot, &proc_entry) == win.TRUE;
        }
    }

    if (opt_proc_id) |proc_id| {
        const proc_handle = win.OpenProcess(0xFFFF, win.FALSE, proc_id);
        if (proc_handle != std.os.windows.INVALID_HANDLE_VALUE) {
            return proc_handle.?;
        } else {
            return failure.FailedToOpenProcess;
        }
    } else {
        return failure.FailedToFindProcess;
    }
}

pub fn findPattern(pattern: []const ?u8, mem_ptr: *anyopaque, mem_len: usize) failure!*anyopaque {
    var i: usize = 0;
    while (i < (mem_len - pattern.len)) : (i += 1) {
        var found: bool = true;

        var n: usize = 0;
        while (n < pattern.len) : (n += 1) {
            if (pattern[n]) |p_byte| {
                const byte: u8 = @as([*]u8, @ptrCast(mem_ptr))[i + n];
                if (byte != p_byte) {
                    found = false;
                    break;
                }
            }
        }

        if (found) return @ptrFromInt(@intFromPtr(mem_ptr) + i);
    }

    return failure.FailedToFindPattern;
}

pub fn findModule(process_handle: *anyopaque, name: [*:0]const u16) failure!*anyopaque {
    const buffer_size: usize = 4096;

    var module_data: [buffer_size]win.HMODULE = std.mem.zeroes([buffer_size]win.HMODULE);
    var data_size: c_ulong = 0;

    const success = win.EnumProcessModulesEx(process_handle, &module_data, buffer_size * @sizeOf(win.HMODULE), &data_size, win.LIST_MODULES_64BIT);

    var exit_code: u32 = 0;
    _ = win.GetExitCodeProcess(process_handle, &exit_code);

    var name_buffer: [buffer_size:0]u16 = undefined;

    if (success == win.TRUE) {
        for (module_data) |optional_module| {
            if (optional_module) |module| {
                name_buffer = std.mem.zeroes([buffer_size:0]u16);
                _ = win.K32GetModuleBaseNameW(process_handle, module, &name_buffer, @truncate(buffer_size));
                if (stringEql(name, &name_buffer)) {
                    return module;
                }
            } else {
                break;
            }
        }
    }

    return error.FailedToFindModule;
}

pub fn getModuleSize(proc_handle: *anyopaque, mod_handle: *anyopaque) failure!u32 {
    var mod_info: win.MODULEINFO = undefined;
    const success = win.K32GetModuleInformation(proc_handle, @ptrCast(@alignCast(mod_handle)), &mod_info, @sizeOf(win.MODULEINFO));

    return if (success == win.FALSE) failure.FailedToRetrieveModuleInfo else mod_info.SizeOfImage;
}

pub fn stringEql(s1: [*:0]const u16, s2: [*:0]const u16) bool {
    var index: usize = 0;
    var match = s1[index] == s2[index];

    while (match and s1[index] != 0) {
        index += 1;
        match = s1[index] == s2[index];
    }

    return match;
}

pub fn printU16(string: [*:0]const u16) void {
    var index: usize = 0;
    var character: u16 = string[index];

    while (character != 0) {
        index += 1;
        character = string[index];
    }

    const utf8 = std.unicode.utf16leToUtf8Alloc(std.heap.page_allocator, string[0..index]) catch unreachable;
    defer std.heap.page_allocator.free(utf8);

    std.debug.print("{s}\n", .{utf8});
}
