# FishHook
<div align="center">A macOS binary repackaging tool for injecting dylib.</div>

## Documentation
FishHook supports macOS10.15+. The libinject.dylib can hook syscalls, such as execve, posix_spawn and other methods of interest to users. The binary fishhook can repack binary to inject the libinject.dylib to hook syscalls.

## Usage
>1. Copy libinject.dylib to the '/usr/local/lib' directory.
>2. Run './fishhook $BinaryPath' to repack.
>3. Execute your binary to check if the system call is replaced.