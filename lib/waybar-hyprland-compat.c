#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <dlfcn.h>
#include <ctype.h>

static ssize_t (*real_write)(int fd, const void *buf, size_t count) = NULL;
static ssize_t (*real_send)(int sockfd, const void *buf, size_t len, int flags) = NULL;

__attribute__((constructor))
static void init(void) {
    real_write = dlsym(RTLD_NEXT, "write");
    real_send = dlsym(RTLD_NEXT, "send");
}

static size_t trim_arg(const char *src, size_t src_len, char *dst, size_t dst_max) {
    if (dst_max == 0) return 0;
    size_t start = 0;
    while (start < src_len && isspace((unsigned char)src[start])) {
        start++;
    }
    size_t end = src_len;
    while (end > start && isspace((unsigned char)src[end - 1])) {
        end--;
    }
    size_t copy_len = end - start;
    if (copy_len >= dst_max) copy_len = dst_max - 1;
    memcpy(dst, src + start, copy_len);
    dst[copy_len] = '\0';
    return copy_len;
}

static int is_unsigned_digits(const char *s) {
    if (!s || !*s) return 0;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        if (!isdigit(*p)) return 0;
    }
    return 1;
}

static int lua_escape_single_quoted(const char *src, char *dst, size_t dst_max) {
    size_t j = 0;
    for (size_t i = 0; src[i] != '\0'; i++) {
        unsigned char c = (unsigned char)src[i];
        if (c == '\\' || c == '\'') {
            if (j + 2 >= dst_max) return -1;
            dst[j++] = '\\';
            dst[j++] = (char)c;
        } else if (c == '\n') {
            if (j + 2 >= dst_max) return -1;
            dst[j++] = '\\';
            dst[j++] = 'n';
        } else if (c == '\r') {
            if (j + 2 >= dst_max) return -1;
            dst[j++] = '\\';
            dst[j++] = 'r';
        } else {
            if (j + 1 >= dst_max) return -1;
            dst[j++] = (char)c;
        }
    }
    if (j >= dst_max) return -1;
    dst[j] = '\0';
    return (int)j;
}

static int format_workspace_expr(const char *raw_arg, char *out_buf, size_t out_max, const char *extra_fields) {
    if (is_unsigned_digits(raw_arg)) {
        return snprintf(out_buf, out_max, "dispatch hl.dsp.focus({ workspace = %s%s })\n", raw_arg, extra_fields);
    }
    const char *ws_val = raw_arg;
    if (strncmp(raw_arg, "name:", 5) == 0 && raw_arg[5] != '\0') {
        ws_val = raw_arg + 5;
    }
    char escaped[384];
    if (lua_escape_single_quoted(ws_val, escaped, sizeof(escaped)) < 0) {
        return 0;
    }
    return snprintf(out_buf, out_max, "dispatch hl.dsp.focus({ workspace = '%s'%s })\n", escaped, extra_fields);
}

static int translate_dispatch(const void *buf, size_t count, char *out_buf, size_t out_max) {
    if (!buf || count < 18 || memcmp(buf, "dispatch ", 9) != 0) {
        return 0;
    }

    const char *cmd = (const char *)buf;
    char arg[256];

    if (count > 19 && memcmp(cmd, "dispatch workspace ", 19) == 0) {
        if (trim_arg(cmd + 19, count - 19, arg, sizeof(arg)) == 0) return 0;
        return format_workspace_expr(arg, out_buf, out_max, "");
    } else if (count > 40 && memcmp(cmd, "dispatch focusworkspaceoncurrentmonitor ", 40) == 0) {
        if (trim_arg(cmd + 40, count - 40, arg, sizeof(arg)) == 0) return 0;
        return format_workspace_expr(arg, out_buf, out_max, ", monitor = 'current'");
    } else if (count >= 31 && memcmp(cmd, "dispatch togglespecialworkspace", 31) == 0 &&
               (count == 31 || isspace((unsigned char)cmd[31]))) {
        size_t arg_len = 0;
        if (count > 31) {
            arg_len = trim_arg(cmd + 31, count - 31, arg, sizeof(arg));
        } else {
            arg[0] = '\0';
        }
        if (arg_len > 0) {
            char escaped[384];
            if (lua_escape_single_quoted(arg, escaped, sizeof(escaped)) < 0) return 0;
            return snprintf(out_buf, out_max, "dispatch hl.dsp.workspace.toggle_special('%s')\n", escaped);
        }
        return snprintf(out_buf, out_max, "dispatch hl.dsp.workspace.toggle_special()\n");
    }

    return 0;
}

ssize_t write(int fd, const void *buf, size_t count) {
    if (!real_write) {
        real_write = dlsym(RTLD_NEXT, "write");
    }

    char new_cmd[512];
    int new_len = translate_dispatch(buf, count, new_cmd, sizeof(new_cmd));
    if (new_len > 0 && (size_t)new_len < sizeof(new_cmd)) {
        ssize_t written = real_write(fd, new_cmd, (size_t)new_len);
        if (written == (ssize_t)new_len) {
            return (ssize_t)count;
        }
        return written;
    }

    return real_write(fd, buf, count);
}

ssize_t send(int sockfd, const void *buf, size_t len, int flags) {
    if (!real_send) {
        real_send = dlsym(RTLD_NEXT, "send");
    }

    char new_cmd[512];
    int new_len = translate_dispatch(buf, len, new_cmd, sizeof(new_cmd));
    if (new_len > 0 && (size_t)new_len < sizeof(new_cmd)) {
        ssize_t sent = real_send(sockfd, new_cmd, (size_t)new_len, flags);
        if (sent == (ssize_t)new_len) {
            return (ssize_t)len;
        }
        return sent;
    }

    return real_send(sockfd, buf, len, flags);
}
