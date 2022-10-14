//
//  syscall_hook.c
//  DylibInject
//
//  Created by ConradSun on 2022/10/12.
//

#include <spawn.h>
#include <unistd.h>
#include <stdio.h>

#ifndef DYLD_INTERPOSE
    #define DYLD_INTERPOSE(_replacement,_replacee) \
        __attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
        __attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };
#endif

static const char *s_repalce_path = "/bin/echo";

int fh_execve(const char *file, char *const *argv, char *const *envp) {
    printf("[FishHook - execve] pid: %d, process path: %s.", getpid(), file);
    return execve(s_repalce_path, argv, envp);
}

int fh_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attr, char *const *argv, char *const *envp) {
    printf("[FishHook - posix_spawn] pid: %d, process path: %s.", *pid, path);
    return posix_spawn(pid, s_repalce_path, actions, attr, argv, envp);
}

DYLD_INTERPOSE(fh_execve, execve)
DYLD_INTERPOSE(fh_posix_spawn, posix_spawn)
