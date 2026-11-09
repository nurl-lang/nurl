### Added

- **`sys_os`, `sys_mem_available` and `sys_mem_total`** (Agora #547,
  stdlib/std/sysinfo.nu). `sys_os` is the system a program was compiled
  for, one of `SYS_OS_LINUX` / `MACOS` / `WINDOWS` / `FREEBSD` / `WASM` /
  `UNIKERNEL`. It is a link-time constant, so a host command line, file
  suffix or cache directory no longer has to guess from `$OS`. The memory
  queries give the bytes the host can hand out without swapping and its
  physical total: MemAvailable / MemTotal on Linux, GlobalMemoryStatusEx
  on Windows, the VM page counts and `hw.memsize` / `hw.physmem` on macOS
  and FreeBSD, and None on wasm and the unikernel. The runtime answers
  them (`nurl_host_os`, `nurl_host_mem`). The gpu package's CPU backend
  used to read `/proc/meminfo` itself, and got 0 on every other system.
