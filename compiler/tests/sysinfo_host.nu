// stdlib/std/sysinfo.nu: sys_os names a known system, and on a hosted
// Linux, macOS, Windows or FreeBSD the host's memory is known, with what
// is available no more than the total. (wasm and the unikernel answer
// None for memory, which is the truth there, so the lines read the same.)
$ `stdlib/core/io.nu`
$ `stdlib/std/sysinfo.nu`

@ main → i {
    : i os ( sys_os )
    : b hosted | | | == os SYS_OS_LINUX == os SYS_OS_MACOS == os SYS_OS_WINDOWS == os SYS_OS_FREEBSD
    : b known | hosted | | == os SYS_OS_WASM == os SYS_OS_UNIKERNEL F
    ( nurl_println ? known `os: known` `os: OTHER` )
    : ~ b mem_ok F
    ?? ( sys_mem_total ) {
        T total → {
            ?? ( sys_mem_available ) {
                T avail → { = mem_ok & > total 0 & >= avail 0 <= avail total }
                F → {}
            }
        }
        F → { = mem_ok ! hosted }
    }
    ( nurl_println ? mem_ok `memory: ok` `memory: WRONG` )
    ^ 0
}
