#include "ArchiveManifestBridge.h"
#include "Vendor/archive.h"
#include "Vendor/archive_entry.h"
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <string.h>

struct DDArchiveInput {
    int descriptor;
    int limited;
    int64_t length;
    int64_t bytesRead;
    double deadline;
    char buffer[65536];
};

static double DDMonotonicTime(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (double)time.tv_sec + (double)time.tv_nsec / 1e9;
}

static int DDInputIsAvailable(struct DDArchiveInput *input) {
    if (DDMonotonicTime() > input->deadline || input->bytesRead > 64 * 1024 * 1024) {
        input->limited = 1;
        return 0;
    }
    return 1;
}

static la_ssize_t DDRead(struct archive *archive, void *data, const void **buffer) {
    (void)archive;
    struct DDArchiveInput *input = data;
    if (!DDInputIsAvailable(input)) return -1;
    ssize_t count = read(input->descriptor, input->buffer, sizeof(input->buffer));
    if (count > 0) input->bytesRead += count;
    *buffer = input->buffer;
    return count;
}

static la_int64_t DDSeek(struct archive *archive, void *data, la_int64_t offset, int whence) {
    (void)archive;
    struct DDArchiveInput *input = data;
    if (!DDInputIsAvailable(input)) return -1;
    off_t position = lseek(input->descriptor, (off_t)offset, whence);
    return position >= 0 && position <= input->length ? position : -1;
}

static la_int64_t DDSkip(struct archive *archive, void *data, la_int64_t request) {
    struct DDArchiveInput *input = data;
    off_t current = lseek(input->descriptor, 0, SEEK_CUR);
    if (current < 0 || request < 0 || request > input->length - current) return -1;
    return DDSeek(archive, data, request, SEEK_CUR) < 0 ? -1 : request;
}

static int DDReadVInt(const unsigned char *bytes, size_t end, size_t *cursor, uint64_t *value) {
    *value = 0;
    for (unsigned int i = 0; i < 10 && *cursor < end; i++) {
        unsigned char byte = bytes[(*cursor)++];
        if (i == 9 && (byte & 0x7f) > 1) return 0;
        *value |= (uint64_t)(byte & 0x7f) << (7 * i);
        if (!(byte & 0x80)) return 1;
    }
    return 0;
}

// libarchive can report EOF after a volume's last complete entry. That is not
// a complete extraction manifest. Reject volumes from their main-header flags.
// RAR5 layout: https://www.rarlab.com/technote.htm (main archive header).
// Returns 1 for a validated single-volume RAR prefix, 0 for other formats, -1
// for unsupported/encrypted/volume RAR. SFX RAR is intentionally not accepted.
static int DDCheckRARHeader(int descriptor, int64_t length) {
    unsigned char bytes[256];
    ssize_t count = pread(descriptor, bytes, sizeof(bytes), 0);
    if (count < 0) return -1;
    static const unsigned char rar3[] = { 0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x00 };
    static const unsigned char rar5[] = { 0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00 };
    if (count >= 7 && memcmp(bytes, rar3, 7) == 0) {
        if (count < 14 || bytes[9] != 0x73) return -1;
        unsigned int flags = bytes[10] | ((unsigned int)bytes[11] << 8);
        return (flags & (0x0001 | 0x0080)) ? -1 : 1;
    }
    if (count < 8 || memcmp(bytes, rar5, 8) != 0) return 0;
    size_t cursor = 12;
    uint64_t size, type, flags, ignored, archiveFlags;
    if (!DDReadVInt(bytes, (size_t)count, &cursor, &size)
        || size > (uint64_t)length || (uint64_t)cursor > (uint64_t)length - size) return -1;
    size_t end = cursor + (size_t)size;
    if (end > (size_t)count) end = (size_t)count;
    if (!DDReadVInt(bytes, end, &cursor, &type) || type != 1
        || !DDReadVInt(bytes, end, &cursor, &flags)) return -1;
    if ((flags & 1) && !DDReadVInt(bytes, end, &cursor, &ignored)) return -1;
    if ((flags & 2) && !DDReadVInt(bytes, end, &cursor, &ignored)) return -1;
    if (!DDReadVInt(bytes, end, &cursor, &archiveFlags)) return -1;
    return (archiveFlags & 3) ? -1 : 1;
}

int DDReadArchiveManifest(const char *path, int maxEntries, int64_t maxExpandedSize,
                          double timeoutSeconds, DDArchiveEntryCallback callback,
                          void *context) {
    struct DDArchiveInput input = { .descriptor = -1 };
    input.descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
    if (input.descriptor < 0) return 1;
    struct stat before;
    if (fstat(input.descriptor, &before) != 0 || !S_ISREG(before.st_mode) || before.st_size <= 0) {
        close(input.descriptor);
        return 1;
    }
    if (flock(input.descriptor, LOCK_SH | LOCK_NB) != 0) {
        close(input.descriptor);
        return 4;
    }
    input.length = before.st_size;
    input.deadline = DDMonotonicTime() + timeoutSeconds;
    int result = 1;
    int count = 0;
    int64_t expandedSize = 0;
    struct archive *archive = archive_read_new();
    if (!archive) goto finished;
    int rarHeader = DDCheckRARHeader(input.descriptor, input.length);
    if (rarHeader < 0) { result = 2; goto freed; }
    // Restrict format/filter registration; never invoke external decompressors.
    archive_read_support_filter_none(archive);
    archive_read_support_format_zip_seekable(archive);
    archive_read_support_format_rar(archive);
    archive_read_support_format_rar5(archive);
    archive_read_support_format_7zip(archive);
    archive_read_set_seek_callback(archive, DDSeek);
    if (archive_read_open2(archive, &input, NULL, DDRead, DDSkip, NULL) != ARCHIVE_OK) goto freed;

    struct archive_entry *entry;
    int status;
    while ((status = archive_read_next_header(archive, &entry)) == ARCHIVE_OK) {
        int format = archive_format(archive) & ARCHIVE_FORMAT_BASE_MASK;
        if ((format == ARCHIVE_FORMAT_RAR || format == ARCHIVE_FORMAT_RAR_V5) && rarHeader != 1) {
            result = 2; goto freed;
        }
        if (!DDInputIsAvailable(&input) || ++count > maxEntries) { result = 3; goto freed; }
        const char *name = archive_entry_pathname_utf8(entry);
        mode_t type = archive_entry_filetype(entry);
        int64_t size = archive_entry_size(entry);
        if (!name || !*name || strnlen(name, 4097) > 4096
            || archive_entry_symlink(entry) || archive_entry_hardlink(entry)
            || archive_entry_is_encrypted(entry)
            || (type != AE_IFREG && type != AE_IFDIR)
            || (type == AE_IFREG && !archive_entry_size_is_set(entry)) || size < 0) {
            result = 2; goto freed;
        }
        if (size > maxExpandedSize - expandedSize) { result = 3; goto freed; }
        expandedSize += size;
        if (callback(name, type == AE_IFDIR, size, context) != 0) { result = 2; goto freed; }
        if (archive_read_data_skip(archive) != ARCHIVE_OK) goto freed;
    }
    if (status == ARCHIVE_EOF && count > 0 && archive_read_has_encrypted_entries(archive) <= 0) result = 0;

freed:
    archive_read_free(archive);
finished:
    if (DDMonotonicTime() > input.deadline) input.limited = 1;
    if (input.limited) result = 3;
    struct stat after;
    if (fstat(input.descriptor, &after) != 0 || before.st_size != after.st_size
        || before.st_mtimespec.tv_sec != after.st_mtimespec.tv_sec
        || before.st_mtimespec.tv_nsec != after.st_mtimespec.tv_nsec
        || before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec
        || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec) result = 4;
    flock(input.descriptor, LOCK_UN);
    close(input.descriptor);
    return result;
}
