//
//  main.c
//  TestExec
//
//  Created by ConradSun on 2025/2/25.
//

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

int main(int argc, const char * argv[]) {
    printf("[FishHook - testexec] Running 'ls -l'\n");
    pid_t pid = fork();
    if (pid == -1) {
        perror("[FishHook - testexec] failed to fork");
        exit(EXIT_FAILURE);
    }

    if (pid == 0) {
        char *args[] = {"ls", "-l", NULL};
        execvp(args[0], args);
        perror("[FishHook - testexec] failed to execvp");
        exit(EXIT_FAILURE);
    } else {
        int status;
        if (waitpid(pid, &status, 0) == -1) {
            perror("[FishHook - testexec] failed to wait for child");
        }
    }

    return EXIT_SUCCESS;
}
