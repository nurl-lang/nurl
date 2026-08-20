// stdlib/std/fswatch.nu — filesystem watching (Linux inotify).
//
// A blocking pull surface over the kernel's inotify queue: add watches
// on directories or files, then call `fswatch_next` in a loop — it
// parks in read(2) until the kernel has an event, so a watcher thread
// costs nothing while idle. Use it for live-reload tools, build
// watchers, or log/spool directory tailing.
//
// Pure libc FFI (inotify_init1 / inotify_add_watch / inotify_rm_watch
// plus read/close from core/posix); no runtime bridge. LINUX ONLY —
// inotify is a Linux kernel API; on other platforms the symbols do not
// exist and this module cannot link (FwUnsupported is reserved for a
// future portable backend).
//
//   ( fswatch_new )                      → ! FsWatch FsWatchErr
//   ( fswatch_add   FsWatch w s path i mask ) → ! i FsWatchErr   (watch descriptor)
//   ( fswatch_rm    FsWatch w i wd )     → ! i FsWatchErr
//   ( fswatch_next  FsWatch w )          → ! FsWatchEvent FsWatchErr  (BLOCKS)
//   ( fswatch_close FsWatch w )          → v   (close fd + free buffers)
//
// FsWatchEvent = { i wd  i mask  String name } — `name` is the entry
// name relative to the watched directory (empty when the watch target
// itself changed). Caller frees `name` (string_free). One read(2) can
// return several packed events; they are cursored out one per call.
//
// Mask bits (subset of <sys/inotify.h>, decimal):
//   FSW_MODIFY 2   FSW_CLOSE_WRITE 8   FSW_MOVED_FROM 64
//   FSW_MOVED_TO 128   FSW_CREATE 256   FSW_DELETE 512
//   FSW_ALL = OR of the above.

$ `stdlib/core/string.nu`
$ `stdlib/core/posix.nu`  // read / close

& `c` @ inotify_init1 i32 flags → i32

& `c` @ inotify_add_watch i32 fd s path u32 mask → i32

& `c` @ inotify_rm_watch i32 fd i32 wd → i32

// ── mask constants (values from <sys/inotify.h>) ────────────────────

: i FSW_MODIFY 2  // IN_MODIFY      0x002
: i FSW_CLOSE_WRITE 8  // IN_CLOSE_WRITE 0x008
: i FSW_MOVED_FROM 64  // IN_MOVED_FROM  0x040
: i FSW_MOVED_TO 128  // IN_MOVED_TO    0x080
: i FSW_CREATE 256  // IN_CREATE      0x100
: i FSW_DELETE 512  // IN_DELETE      0x200
: i FSW_ALL 970  // OR of all six above

// Kernel event buffer: one read(2) fills up to this many bytes with
// packed struct inotify_event records.
: i FSW_BUF_CAP 4096

: | FsWatchErr {
    FwInit  // inotify_init1() failed
    FwWatch  // inotify_add_watch() / inotify_rm_watch() failed
    FwRead  // read() failed or returned a malformed event
    FwClosed  // fd reached EOF / watcher already closed
    FwUnsupported  // reserved: no inotify on this platform
}

@ fswatch_err_name FsWatchErr e → s {
    ^ ?? e {
        FwInit → `FwInit`
        FwWatch → `FwWatch`
        FwRead → `FwRead`
        FwClosed → `FwClosed`
        FwUnsupported → `FwUnsupported`
    }
}

// Heap control block (FsWatch is a copyable handle over it).
//   fd  — inotify fd (-1 once closed)
//   buf — event buffer address, held as i64 (a mutable *u binding
//         miscompiles across reassignment; cast per use)
//   lim — bytes valid in buf
//   pos — read cursor into buf
: FsWatchImpl { i fd i buf i lim i pos }

: FsWatch { s ctl }

: FsWatchEvent { i wd i mask String name }

// ── internal ────────────────────────────────────────────────────────

// u32 little-endian load from the event buffer.
@ __fsw_u32 * u p i off → i {
    : i b0 # i . p off
    : i b1 # i . p + off 1
    : i b2 # i . p + off 2
    : i b3 # i . p + off 3
    : i hi + << b3 24 << b2 16
    : i lo + << b1 8 b0
    ^ + hi lo
}

// ── API ─────────────────────────────────────────────────────────────

@ fswatch_new → !FsWatch FsWatchErr {
    : i32 fd0 ( inotify_init1 # i32 0 )
    ? < # i fd0 0 { ^ @ !FsWatch FsWatchErr { F FwInit } } {}
    : *FsWatchImpl st # *FsWatchImpl ( nurl_alloc Z FsWatchImpl )
    = . st fd # i fd0
    = . st buf # i ( nurl_alloc FSW_BUF_CAP )
    = . st lim 0
    = . st pos 0
    ^ @ !FsWatch FsWatchErr { T @ FsWatch { # s st } }
}

@ fswatch_add FsWatch w s path i mask → !i FsWatchErr {
    : *FsWatchImpl st # *FsWatchImpl . w ctl
    ? < . st fd 0 { ^ @ !i FsWatchErr { F FwClosed } } {}
    : i32 wd ( inotify_add_watch # i32 . st fd path # u32 mask )
    ? < # i wd 0 { ^ @ !i FsWatchErr { F FwWatch } } {}
    ^ @ !i FsWatchErr { T # i wd }
}

@ fswatch_rm FsWatch w i wd → !i FsWatchErr {
    : *FsWatchImpl st # *FsWatchImpl . w ctl
    ? < . st fd 0 { ^ @ !i FsWatchErr { F FwClosed } } {}
    : i32 r ( inotify_rm_watch # i32 . st fd # i32 wd )
    ? < # i r 0 { ^ @ !i FsWatchErr { F FwWatch } } {}
    ^ @ !i FsWatchErr { T 0 }
}

// Pop the next event; BLOCKS in read(2) when the buffer is drained.
// struct inotify_event: { i32 wd; u32 mask; u32 cookie; u32 len;
// char name[len] } — 16-byte header, name NUL-padded to `len`.
@ fswatch_next FsWatch w → !FsWatchEvent FsWatchErr {
    : *FsWatchImpl st # *FsWatchImpl . w ctl
    ? < . st fd 0 { ^ @ !FsWatchEvent FsWatchErr { F FwClosed } } {}
    ~ >= . st pos . st lim {
        : i n ( read . st fd # *u . st buf FSW_BUF_CAP )
        ? == n 0 { ^ @ !FsWatchEvent FsWatchErr { F FwClosed } } {}
        ? < n 0 { ^ @ !FsWatchEvent FsWatchErr { F FwRead } } {}
        = . st pos 0
        = . st lim n
    }
    ? > + . st pos 16 . st lim { ^ @ !FsWatchEvent FsWatchErr { F FwRead } } {}
    : *u p # *u + . st buf . st pos
    : i wd ( __fsw_u32 p 0 )
    : i mask ( __fsw_u32 p 4 )
    : i namelen ( __fsw_u32 p 12 )
    ? > + + . st pos 16 namelen . st lim { ^ @ !FsWatchEvent FsWatchErr { F FwRead } } {}
    : String name ( string_with_cap + namelen 1 )
    : ~ i k 0
    : ~ b more T
    ~ & more < k namelen {
        : i ch # i . p + 16 k
        ? == ch 0 { = more F } { ( string_push_char name ch ) }
        = k + k 1
    }
    = . st pos + . st pos + 16 namelen
    ^ @ !FsWatchEvent FsWatchErr { T @ FsWatchEvent { wd mask name } }
}

@ fswatch_close FsWatch w → v {
    : *FsWatchImpl st # *FsWatchImpl . w ctl
    ? >= . st fd 0 { : i _c ( close . st fd ) } {}
    = . st fd -1
    ( nurl_free # *u . st buf )
    ( nurl_free # *u . w ctl )
}
