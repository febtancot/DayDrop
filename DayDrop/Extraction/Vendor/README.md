# libarchive public headers

`archive.h` and `archive_entry.h` are unmodified public headers from libarchive
3.7.4, tag commit `313aa1fa10b657de791e3202c168a6c833bc3543`:
https://github.com/libarchive/libarchive/tree/v3.7.4/libarchive

The macOS SDK exports `libarchive.2.tbd` but does not ship these headers. DayDrop
links the system library; it does not bundle another archive decoder. Only the
local read-only ZIP, RAR/RAR5, and 7z header APIs are used. The system OS version
determines the available decoder behavior. Copyright notices remain in the
headers; the upstream license is also bundled in `Resources/Licenses/libarchive.txt`.
