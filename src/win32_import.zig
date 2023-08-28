pub usingnamespace @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "");
    @cInclude("windows.h");
    @cInclude("tlhelp32.h");
    @cInclude("psapi.h");
    @cInclude("shlwapi.h");
});

pub const L = @import("std").unicode.utf8ToUtf16LeStringLiteral;
