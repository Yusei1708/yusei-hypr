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

static int translate_dispatch(const void *buf, size_t count, char *out_buf, size_t out_max) {
    if (count < 18 || !buf || memcmp(buf, "dispatch ", 9) != 0) {
        return 0;
    }

    const char *cmd = (const char *)buf;
    char arg[256];

    if (strncmp(cmd, "dispatch workspace ", 19) == 0) {
        size_t arg_len = count - 19;
        if (arg_len >= sizeof(arg)) arg_len = sizeof(arg) - 1;
        memcpy(arg, cmd + 19, arg_len);
        arg[arg_len] = '\0';
        while (arg_len > 0 && (arg[arg_len - 1] == '\n' || arg[arg_len - 1] == '\r' || isspace((unsigned char)arg[arg_len - 1]))) {
            arg[--arg_len] = '\0';
        }

        if (arg[0] == 'e' || arg[0] == 'm' || arg[0] == '+' || arg[0] == '-') {
            return snprintf(out_buf, out_max, "dispatch hl.dsp.focus({ workspace = '%s' })\n", arg);
        } else if (strncmp(arg, "name:", 5) == 0) {
            return snprintf(out_buf, out_max, "dispatch hl.dsp.focus({ workspace = '%s' })\n", arg + 5);
        } else {
            return snprintf(out_buf, out_max, "dispatch hl.dsp.focus({ workspace = %s })\n", arg);
        }
    } else if (strncmp(cmd, "dispatch focusworkspaceoncurrentmonitor ", 39) == 0) {
        size_t arg_len = count - 39;
        if (arg_len >= sizeof(arg)) arg_len = sizeof(arg) - 1;
        memcpy(arg, cmd + 39, arg_len);
        arg[arg_len] = '\0';
        while (arg_len > 0 && (arg[arg_len - 1] == '\n' || arg[arg_len - 1] == '\r' || isspace((unsigned char)arg[arg_len - 1]))) {
            arg[--arg_len] = '\0';
        }
        if (strncmp(arg, "name:", 5) == 0) {
            return snprintf(out_buf, out_max, "dispatch hl.dsp.focus({ workspace = '%s', monitor = 'current' })\n", arg + 5);
        } else {
            return snprintf(out_buf, out_max, "dispatch hl.dsp.focus({ workspace = %s, monitor = 'current' })\n", arg);
        }
    } else if (strncmp(cmd, "dispatch togglespecialworkspace", 30) == 0) {
        size_t arg_len = 0;
        if (count > 31 && cmd[30] == ' ') {
            arg_len = count - 31;
            if (arg_len >= sizeof(arg)) arg_len = sizeof(arg) - 1;
            memcpy(arg, cmd + 31, arg_len);
            arg[arg_len] = '\0';
            while (arg_len > 0 && (arg[arg_len - 1] == '\n' || arg[arg_len - 1] == '\r' || isspace((unsigned char)arg[arg_len - 1]))) {
                arg[--arg_len] = '\0';
            }
        } else {
            arg[0] = '\0';
        }
        if (arg_len > 0) {
            return snprintf(out_buf, out_max, "dispatch hl.dsp.workspace.toggle_special('%s')\n", arg);
        } else {
            return snprintf(out_buf, out_max, "dispatch hl.dsp.workspace.toggle_special()\n");
        }
    }

    return 0;
}

ssize_t write(int fd, const void *buf, size_t count) {
    if (!real_write) {
        real_write = dlsym(RTLD_NEXT, "write");
    }

    char new_cmd[512];
    int new_len = translate_dispatch(buf, count, new_cmd, sizeof(new_cmd));
    if (new_len > 0) {
        return real_write(fd, new_cmd, new_len);
    }

    return real_write(fd, buf, count);
}

ssize_t send(int sockfd, const void *buf, size_t len, int flags) {
    if (!real_send) {
        real_send = dlsym(RTLD_NEXT, "send");
    }

    char new_cmd[512];
    int new_len = translate_dispatch(buf, len, new_cmd, sizeof(new_cmd));
    if (new_len > 0) {
        return real_send(sockfd, new_cmd, new_len, flags);
    }

    return real_send(sockfd, buf, len, flags);
}
