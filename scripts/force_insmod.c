#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

#define MODULE_INIT_IGNORE_MODVERSIONS  1
#define MODULE_INIT_IGNORE_VERMAGIC     2

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <module.ko> [args...]\n", argv[0]);
        return 1;
    }

    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "Error opening %s: %s\n", argv[1], strerror(errno));
        return 1;
    }

    // gather args
    char args[1024] = {0};
    for (int i = 2; i < argc; i++) {
        strncat(args, argv[i], sizeof(args) - strlen(args) - 1);
        strncat(args, " ", sizeof(args) - strlen(args) - 1);
    }

    int flags = MODULE_INIT_IGNORE_MODVERSIONS | MODULE_INIT_IGNORE_VERMAGIC;
    int ret = syscall(__NR_finit_module, fd, args, flags);
    if (ret != 0) {
        fprintf(stderr, "finit_module failed for %s: %s\n", argv[1], strerror(errno));
        close(fd);
        return 1;
    }

    printf("Successfully force-loaded %s\n", argv[1]);
    close(fd);
    return 0;
}
