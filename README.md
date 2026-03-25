# FishHook

<div align="center">A tool for re-packaging binary files on macOS to inject dynamic libraries (dylib).</div>

## Documentation

FishHook supports macOS 11+, and allows for the injection of binaries for both x86_64 and arm64 architectures. In theory, it supports the injection of all Mach-O format binaries for these two architectures, but does not support the arm64e architecture.

The binary `fishhook` can repack binaries to inject `libinject.dylib`, which is capable of hooking system calls. The `libinject.dylib` can intercept system calls such as `execve`, `posix_spawn`, and other methods of interest to users. The binary `testexec` is used for testing the injection process.

## Usage

>1. Copy libinject.dylib to the '/usr/local/lib' directory.
>2. Run './fishhook $BinaryPath' to repack.
>3. Execute your repacked binary to check if the system call is replaced.