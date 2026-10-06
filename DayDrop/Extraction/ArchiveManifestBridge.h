#ifndef DAYDROP_ARCHIVE_MANIFEST_BRIDGE_H
#define DAYDROP_ARCHIVE_MANIFEST_BRIDGE_H

#include <stdint.h>

/// Returns nonzero to abort; strings are valid only during the callback.
typedef int (*DDArchiveEntryCallback)(const char *path, int isDirectory,
                                      int64_t size, void *context);

/// Reads headers only. No extraction, password prompt, or external programs.
/// 0 = complete; 1 = unreadable; 2 = unsafe/encrypted; 3 = resource limit; 4 = busy.
int DDReadArchiveManifest(const char *path, int maxEntries, int64_t maxExpandedSize,
                          double timeoutSeconds, DDArchiveEntryCallback callback,
                          void *context);

#endif
