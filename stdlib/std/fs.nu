// stdlib/std/fs.nu — non-fatal filesystem API
//
// Wraps the bare `nurl_file_*` runtime calls in the `! T IoErr` discipline
// shared by the rest of the stdlib. Errors are classified via the runtime
// helper `nurl_errno_kind`, which maps the libc errno of the most recent
// failing call to one of the `IoErr` variants.
//
// The handle-based runtime calls (`nurl_file_open`, `nurl_file_write`,
// `nurl_file_close`) are still available raw; this module only adds the
// safe one-shot variants used by application code.
//
//   ( read_file path )           → ! String IoErr   owned String, '\0' stripped at len
//   ( write_file path content )  → ! v IoErr        truncates / creates
//   ( append_file path content ) → ! v IoErr        opens "a"; creates if missing
//   ( file_exists path )         → b
//   ( file_size path )           → ! i IoErr        bytes; NotFound if stat fails
//   ( file_delete path )         → ! v IoErr        succeeds even when missing
//                                                    (matches Rust's `remove_file`?
//                                                    no — `remove` returns 0 only when
//                                                    the entry was actually unlinked,
//                                                    so we surface ENOENT as NotFound)
//   ( dir_create path )          → ! v IoErr        mkdir 0755; AlreadyExists if exists
//   ( dir_create_all path )      → ! v IoErr        mkdir -p: every missing parent;
//                                                    an existing directory is not an error
//   ( dir_remove_all path )      → ! v IoErr        recursive rm -rf of a directory tree
//                                                    (also unlinks a plain file / symlink)
//
// Streaming reads — for inputs too large to slurp with read_file:
//   ( file_open path )           → ! File IoErr     open a file for binary reading
//   ( file_read_chunk f n )      → ! ( Vec u ) IoErr  up to n bytes; empty Vec at EOF
//   ( file_eof f )               → b                T once the stream is drained
//   ( file_close f )             → v                close the handle
//
// Examples:
//   : ! String IoErr r ( read_file `data.txt` )
//   ?? r {
//     T s → ( nurl_print ( string_data s ) )
//     F e → ( nurl_eprintln ( io_err_msg # IoErr e ) )
//   }
//
// Ownership: read_file returns an OWNED `String`; the caller is
// responsible for `string_free`-ing it (or letting auto-drop do so at
// scope exit). write_file/append_file BORROW the content string —
// callers may pass `( string_data s )` from an owned String without
// transferring ownership.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/std/path.nu`
$ `stdlib/core/posix.nu`  // open / lseek / mmap / munmap + posix_const

// errno-kind → IoErr enum value. Order matches `nurl_errno_kind` in
// runtime.c (NotFound=0, PermissionDenied=1, AlreadyExists=2,
// Interrupted=3, UnexpectedEof=4, WriteFailed=5, ReadFailed=6, Other=7).
@ __io_err_of_kind i k → IoErr {
    ? == k 0 { ^ @ IoErr { NotFound } } {}
    ? == k 1 { ^ @ IoErr { PermissionDenied } } {}
    ? == k 2 { ^ @ IoErr { AlreadyExists } } {}
    ? == k 3 { ^ @ IoErr { Interrupted } } {}
    ? == k 4 { ^ @ IoErr { UnexpectedEof } } {}
    ? == k 5 { ^ @ IoErr { WriteFailed } } {}
    ? == k 6 { ^ @ IoErr { ReadFailed } } {}
    ^ @ IoErr { Other }
}

// Win32 / WASI fallback for `read_file` — same fopen + fseek(SEEK_END)
// + ftell + fread + fclose pattern the old `nurl_read_file_safe`
// followed. Allocates exactly `len + 1` bytes (matches what
// `string_from_take`'s cap expects) and writes a trailing NUL.
@ __read_file_fread_pure s path → s {
    ? == # i path 0 { ^ # s 0 } {}
    : s fp ( fopen path `rb` )
    ? == # i fp 0 { ^ # s 0 } {}
    : i32 sr ( fseek fp 0 # i32 2 )
    ? != sr # i32 0 {
        : i32 _u ( fclose fp )
        ^ # s 0
    } {}
    : i sz ( ftell fp )
    ? < sz 0 {
        : i32 _u ( fclose fp )
        ^ # s 0
    } {}
    : i32 _r ( fseek fp 0 # i32 0 )
    : s buf ( nurl_alloc + sz 1 )
    ? == # i buf 0 {
        : i32 _u ( fclose fp )
        ^ # s 0
    } {}
    : i got ? > sz 0 ( fread buf 1 sz fp ) 0
    : i32 _u ( fclose fp )
    : *u bp # *u buf
    = . bp got # u 0
    ^ buf
}

// Pure-NURL mmap-backed file read (PURIFY §4 batch 5). On POSIX the
// kernel page-cache is mapped read-only into the process, sequential
// access is hinted via `madvise(MADV_SEQUENTIAL)`, and the bytes are
// copied into a malloc'd `nurl_alloc` buffer that the caller wraps
// via `string_from_take` (no second copy). Returns 0 on any failure
// — the gate `read_file` below classifies it via `nurl_errno_kind`.
//
// The size is learned via `lseek(fd, 0, SEEK_END)` rather than
// `fstat(fd)` so the implementation doesn't need to know the
// platform-specific `struct stat::st_size` offset. SEEK_END = 2 is
// universal POSIX.
@ __read_file_mmap_pure s path → s {
    ? == # i path 0 { ^ # s 0 } {}
    : i32 fd ( open path # i32 ( posix_const `O_RDONLY` ) # i32 0 )
    ? < fd # i32 0 { ^ # s 0 } {}
    : i sz ( lseek fd 0 # i32 2 )
    ? < sz 0 {
        : i _c ( close # i fd )
        ^ # s 0
    } {}
    ? == sz 0 {
        // Empty file: return a freshly-allocated 1-byte NUL buffer.
        : i _c ( close # i fd )
        : s buf ( nurl_alloc 1 )
        ? != # i buf 0 {
            : *u bp # *u buf
            = . bp 0 # u 0
        } {}
        ^ buf
    } {}
    : *u m ( mmap # *u 0 sz
    # i32 ( posix_const `PROT_READ` )
    # i32 ( posix_const `MAP_PRIVATE` )
    fd 0 )
    : i _c ( close # i fd )
    // MAP_FAILED = (void*)-1 on every supported target; check via ptrtoint.
    ? == # i m -1 { ^ # s 0 } {}
    // Best-effort read-ahead hint; ignore the return.
    : i32 _mr ( madvise m sz # i32 ( posix_const `MADV_SEQUENTIAL` ) )
    : s buf ( nurl_alloc + sz 1 )
    ? == # i buf 0 {
        : i32 _u ( munmap m sz )
        ^ # s 0
    } {}
    ( memcpy # *u buf m sz )
    : *u bp # *u buf
    = . bp sz # u 0
    : i32 _u ( munmap m sz )
    ^ buf
}

// `raw` is either the malloc'd file contents (owned) or NULL on failure.
// Cast to i64 to detect NULL — calling nurl_str_len on NULL would crash.
@ read_file s path → !String IoErr {
    // POSIX path: pure-NURL mmap → memcpy. Win32 / WASI use a
    // fopen+fseek+fread fallback (also pure NURL) since
    // `MAP_PRIVATE` is unavailable in `nurl_native_constant` there.
    : ~ s raw # s 0
    ? != ( posix_const `MAP_PRIVATE` ) -1 {
        = raw # s ( __read_file_mmap_pure path )
    } {
        = raw ( __read_file_fread_pure path )
    }
    : i p # i raw
    ? == p 0 {
        : IoErr e ( __io_err_of_kind ( errno_kind ) )
        ^ @ !String IoErr { F e }
    } {}
    // Wrap the malloc'd buffer in a String WITHOUT copying. The
    // buffer was allocated as `nurl_str_len raw + 1` (NUL pad),
    // so cap = len + 1 matches the malloc size — `string_free`
    // can `nurl_free` it correctly later. Saves ~33 ms / 100 MB
    // vs the previous `string_from raw; nurl_free raw` path
    // which copied every byte.
    : i n ( nurl_str_len raw )
    : String out ( string_from_take raw + n 1 )
    ^ @ !String IoErr { T out }
}

// Always opens the file in binary mode (`wb`/`ab`). On POSIX this is a
// no-op; on Windows the C runtime would otherwise translate every `\n`
// in the payload to `\r\n` under the text-mode `w`/`a` flag, which
// corrupts UTF-8 multibyte sequences and shifts byte offsets emitted by
// downstream parsers (notably nurlc — a `→` arrow sitting next to a
// translated newline appears at the wrong column and is rejected as
// "expected type"). Cross-platform NURL programs writing to disk almost
// always want LF preserved exactly as written, so binary is the right
// default. Callers that need CRLF must produce it explicitly in the
// payload.
// Non-fatal write: opens `path` in binary mode (`wb` truncate or `ab`
// append) and writes `content`'s NUL-terminated bytes. Returns 0 on
// success or -1 on any failure (open, partial write, or close); the
// classification routes through `nurl_errno_kind` like every other
// `IoErr` boundary. The body is pure NURL — `fopen` / `fwrite` /
// `fclose` are declared in `nurlc.nu`'s preamble and reach libc directly.
@ __write_file_pure s path s content s mode → i {
    ? || == # i path 0 || == # i content 0 == # i mode 0 { ^ -1 } {}
    : s fp ( fopen path mode )
    ? == # i fp 0 { ^ -1 } {}
    : i n ( nurl_str_len content )
    ? > n 0 {
        : i got ( fwrite content 1 n fp )
        ? != got n {
            : i32 _cr ( fclose fp )
            ^ -1
        } {}
    } {}
    : i32 cr ( fclose fp )
    ? != cr # i32 0 { ^ -1 } {}
    ^ 0
}

@ write_file s path s content → !v IoErr {
    : i rc ( __write_file_pure path content `wb` )
    ? == rc 0 {
        ^ @ !v IoErr { T 0 }
    } {}
    : IoErr e ( __io_err_of_kind ( errno_kind ) )
    ^ @ !v IoErr { F e }
}

@ append_file s path s content → !v IoErr {
    : i rc ( __write_file_pure path content `ab` )
    ? == rc 0 {
        ^ @ !v IoErr { T 0 }
    } {}
    : IoErr e ( __io_err_of_kind ( errno_kind ) )
    ^ @ !v IoErr { F e }
}

@ file_exists s path → b {
    ^ != 0 ( nurl_file_exists path )
}

// Byte length of a regular file. Implementation: open in binary mode,
// seek to end, query position, close. Avoids the `stat(2)` path
// entirely because `struct stat`'s `st_size` field offset varies by
// platform (Linux x86_64 = 48, macOS = 96, mingw layout different
// again) and porting that offset table buys nothing — SEEK_END is a
// universal POSIX value (2) honoured by every libc stdio we target.
// Directories and other non-regular files yield the same "fopen
// succeeded" outcome as on POSIX (ftell on a directory is
// implementation-defined; the previous stat-based path returned the
// directory's allocation size 4096 — a behavioural difference NURL
// callers should not be relying on).
@ __file_size_pure s path → i {
    ? == # i path 0 { ^ -1 } {}
    : s fp ( fopen path `rb` )
    ? == # i fp 0 { ^ -1 } {}
    : i32 sr ( fseek fp 0 # i32 2 )
    ? != sr # i32 0 {
        : i32 _u ( fclose fp )
        ^ -1
    } {}
    : i sz ( ftell fp )
    : i32 _cr ( fclose fp )
    ^ sz
}

@ file_size s path → !i IoErr {
    : i n ( __file_size_pure path )
    ? < n 0 {
        : IoErr e ( __io_err_of_kind ( errno_kind ) )
        ^ @ !i IoErr { F e }
    } {}
    ^ @ !i IoErr { T n }
}

// Best-effort delete. `nurl_file_del` (libc `remove`) doesn't surface
// errno reliably across platforms, so callers wanting to distinguish
// "did not exist" from "still there" should call `file_exists` first.
@ file_delete s path → !v IoErr {
    ? == ( nurl_file_exists path ) 0 {
        ^ @ !v IoErr { F @ IoErr { NotFound } }
    } {}
    ( nurl_file_del path )
    ^ @ !v IoErr { T 0 }
}

@ dir_create s path → !v IoErr {
    : i rc ( nurl_dir_create path )
    ? == rc 0 {
        ^ @ !v IoErr { T 0 }
    } {}
    : IoErr e ( __io_err_of_kind ( errno_kind ) )
    ^ @ !v IoErr { F e }
}

// POSIX symlink(2) — `target` is what the link points TO (stored
// verbatim in the symlink), `linkpath` is the new symlink entry to
// create. Returns 0 on success, -1 on failure with errno set.
// Windows is NOT supported here; CreateSymbolicLinkW needs a privilege
// (`SeCreateSymbolicLinkPrivilege`) most accounts lack — Win32 users
// of nurlpkg should fall back to copying.
& `c` @ symlink s target s linkpath → i32

// Create a symbolic link at `linkpath` pointing to `target`. Returns
// IoErr {AlreadyExists} if the entry already exists (errno = EEXIST),
// {PermissionDenied} on EACCES, {Other} for everything else.
@ fs_symlink s target s linkpath → !v IoErr {
    : i32 rc ( symlink target linkpath )
    ? == rc 0 {
        ^ @ !v IoErr { T 0 }
    } {}
    : IoErr e ( __io_err_of_kind ( errno_kind ) )
    ^ @ !v IoErr { F e }
}

// POSIX readlink(2) — writes the symlink's target into `buf` (NOT
// NUL-terminated) and returns the byte count, or -1 with errno set
// (EINVAL when `path` is not a symlink). `bufsiz` caps the write.
& `c` @ readlink s path s buf i bufsiz → i

// Read the target a symbolic link points to, as an owned String.
// Returns IoErr {Other} when `path` is not a symlink (errno = EINVAL),
// {NotFound} when it doesn't exist, etc. The target is captured into a
// zero-filled PATH_MAX buffer so the returned String is always NUL-
// terminated; targets longer than 4095 bytes (above the Linux symlink
// ceiling) are truncated.
@ fs_readlink s path → !String IoErr {
    : i cap 4096
    : s buf ( nurl_zalloc + cap 1 )
    : i n ( readlink path buf cap )
    ? < n 0 {
        ( nurl_free buf )
        : IoErr e ( __io_err_of_kind ( errno_kind ) )
        ^ @ !String IoErr { F e }
    } {}
    : String out ( string_from buf )
    ( nurl_free buf )
    ^ @ !String IoErr { T out }
}

// Remove an empty directory. Returns NotFound when missing, Other when
// the directory is non-empty (errno = ENOTEMPTY) — the errno-kind table
// folds the latter into Other rather than introducing a new variant.
@ dir_remove s path → !v IoErr {
    : i rc ( nurl_dir_remove path )
    ? == rc 0 {
        ^ @ !v IoErr { T 0 }
    } {}
    : IoErr e ( __io_err_of_kind ( errno_kind ) )
    ^ @ !v IoErr { F e }
}

// POSIX dir-list helpers — pure-NURL drivers over opendir/readdir/closedir.
// PURIFY §13 batch 3 (2026-05-24): replaced the C-side iterator with a
// loop in NURL that filters "." / ".." and copies each name into an
// owned String. The `d_name` field offset within `struct dirent` varies
// by platform (Linux glibc = 19, macOS = 21), so a 1-line C accessor
// (`nurl_dirent_name` in runtime.c) bridges it without porting the
// offset table into NURL.
@ __dir_list_pure_posix s path → !( Vec String ) IoErr {
    : s d ( opendir path )
    ? == # i d 0 {
        : IoErr e ( __io_err_of_kind ( errno_kind ) )
        ^ @ !( Vec String ) IoErr { F e }
    } {}
    : ( Vec String ) out ( vec_new [String] )
    : ~ b going T
    ~ going {
        : s de ( readdir d )
        ? == # i de 0 {
            = going F
        } {
            : s name ( nurl_dirent_name de )
            ? != # i name 0 {
                : i c0 ( nurl_str_get name 0 )
                : i n ( nurl_str_len name )
                : ~ b skip F
                ? == c0 46 {
                    ? == n 1 { = skip T } {
                        ? & == n 2 == ( nurl_str_get name 1 ) 46 { = skip T } {}
                    }
                } {}
                ? ! skip {
                    ( vec_push [String] out ( string_from name ) )
                } {}
            } {}
        }
    }
    : i32 _c ( closedir d )
    ^ @ !( Vec String ) IoErr { T out }
}

// List directory entries (excluding "." and "..") as owned Strings.
// The returned Vec is owned: free the elements first via vec_free_with
// + string_free, then drop the Vec itself. Order is platform-defined
// (POSIX returns the on-disk order; Windows returns FindFirstFile order).
// Callers that want a stable order should sort_by cmp_string afterwards.
@ dir_list s path → !( Vec String ) IoErr {
    // POSIX: drive opendir/readdir/closedir in pure NURL via
    // `__dir_list_pure_posix`. Win32 / WASI route through the runtime's
    // `nurl_dir_list_*` opaque-handle trio (FindFirstFile state cache).
    ? != ( posix_const `O_RDONLY` ) -1 {
        ^ ( __dir_list_pure_posix path )
    } {}
    : i h ( nurl_dir_list_open path )
    ? == h 0 {
        : IoErr e ( __io_err_of_kind ( errno_kind ) )
        ^ @ !( Vec String ) IoErr { F e }
    } {}
    : ( Vec String ) out ( vec_new [String] )
    : ~ b going T
    ~ going {
        : s raw ( nurl_dir_list_next h )
        : i p # i raw
        ? == p 0 {
            = going F
        } {
            ( vec_push [String] out ( string_from raw ) )
            ( nurl_free raw )
        }
    }
    ( nurl_dir_list_close h )
    ^ @ !( Vec String ) IoErr { T out }
}

// ── Binary I/O ──────────────────────────────────────────────────────
//
// Read and write opaque byte buffers (`( Vec u )`). NUL bytes are kept
// verbatim — these are the right primitives for images, archives, msgpack
// and any other non-text payload. For UTF-8 text use read_file/write_file.
//
// Memory model: read_file_bytes returns an OWNED Vec[u]; the caller must
// `( vec_free [u] v )` (or let auto-drop do so at scope exit). The
// runtime buffer is freed inside read_file_bytes — callers never see it.
// write_file_bytes BORROWS its byte buffer.

// PURIFY (2026-05-24): read_file_bytes / write_file_bytes /
// append_file_bytes now call fopen / fseek / ftell / fread / fwrite /
// fclose directly via libc FFI — no more `nurl_read_file_bytes` /
// `nurl_write_file_bytes` / `nurl_last_bytes_len` sideband in C.
// fread writes into the Vec[u]'s data buffer directly; vec_set_len
// records the actual byte count.
@ read_file_bytes s path → !( Vec u ) IoErr {
    : s f # s ( fopen path `rb` )
    ? == # i f 0 {
        : IoErr e ( __io_err_of_kind ( errno_kind ) )
        ^ @ !( Vec u ) IoErr { F e }
    } {}
    : i32 _e1 ( fseek f 0 # i32 2 )  // SEEK_END
    : i sz ( ftell f )
    : i32 _e2 ( fseek f 0 # i32 0 )  // SEEK_SET
    ? < sz 0 {
        : i32 _ ( fclose f )
        : IoErr e ( __io_err_of_kind ( errno_kind ) )
        ^ @ !( Vec u ) IoErr { F e }
    } {}
    : i cap_n ? > sz 0 sz 1
    : ( Vec u ) v ( vec_with_cap [u] cap_n )
    : *u dst ( vec_data [u] v )
    : i got ? > sz 0 ( fread # s dst 1 sz f ) 0
    : i32 _r ( fclose f )
    : b _ok ( vec_set_len [u] v got )
    ^ @ !( Vec u ) IoErr { T v }
}

@ write_file_bytes s path ( Vec u ) v → !v IoErr {
    ^ ( __write_bytes path v `wb` )
}

@ append_file_bytes s path ( Vec u ) v → !v IoErr {
    ^ ( __write_bytes path v `ab` )
}

@ __write_bytes s path ( Vec u ) v s mode → !v IoErr {
    : s f # s ( fopen path mode )
    ? == # i f 0 {
        : IoErr e ( __io_err_of_kind ( errno_kind ) )
        ^ @ !v IoErr { F e }
    } {}
    : i n ( vec_len [u] v )
    ? > n 0 {
        : *u data ( vec_data [u] v )
        : i got ( fwrite # s data 1 n f )
        ? != got n {
            : i32 _ ( fclose f )
            : IoErr e ( __io_err_of_kind ( errno_kind ) )
            ^ @ !v IoErr { F e }
        } {}
    } {}
    : i32 rc ( fclose f )
    ? != rc # i32 0 {
        : IoErr e ( __io_err_of_kind ( errno_kind ) )
        ^ @ !v IoErr { F e }
    } {}
    ^ @ !v IoErr { T 0 }
}

// ── Recursive directory operations ──────────────────────────────────
//
// dir_create_all is mkdir -p; dir_remove_all is rm -rf. Both compose the
// single-level primitives above. dir_remove_all classifies every entry
// with `nurl_path_type`, which uses lstat — a symbolic link is unlinked,
// never followed, so the walk can never escape the tree it was handed.

// libc unlink(2): removes a file or symlink entry; 0 on success, -1 with
// errno set. Used for non-directory entries during recursive removal —
// nurl_file_del discards its return code, and file_delete's stat-based
// existence probe would mis-report a dangling symlink as NotFound.
& `c` @ unlink s path → i32

// Runtime filesystem helpers (resolved from runtime.o; libc is always
// linked). nurl_path_type: 0 missing, 1 file, 2 dir, 3 symlink, 4 other.
& `c` @ nurl_path_type s path → i

// ── nurl_file_* via libc stdio ─────────────────────────────────────
// fopen / fclose / fputs / fwrite / fputc / fread / feof come from
// the nurlc preamble (globally declared). Handles are *v throughout.

// fopen wrapper. Returns NULL handle on failure (NURL callers check
// via `# i h == 0`).
@ nurl_file_open s path s mode → *v {
    : s h # s ( fopen path mode )
    ^ # *v h
}

@ nurl_file_close * v h → v {
    ? != 0 # i h { : i32 _ ( fclose # s h ) } {}
}

// fputs the NUL-terminated `str` to `h`. NULL-safe on both args.
@ nurl_file_write * v h s str → v {
    ? & != 0 # i h != 0 # i str {
        : i32 _ ( fputs str # s h )
    } {}
}

// fwrite `len` bytes from `p` to `h`. NULL-safe; len<=0 is a no-op.
@ nurl_file_write_range * v h s p i len → v {
    ? & & != 0 # i h != 0 # i p > len 0 {
        : i _ ( fwrite p 1 len # s h )
    } {}
}

// fputc one byte. NULL-safe.
@ nurl_file_write_byte * v h i c → v {
    ? != 0 # i h { : i32 _ ( fputc # i32 c # s h ) } {}
}

@ nurl_file_eof * v h → i {
    ? == # i h 0 { ^ 1 } {}
    ^ ? != 0 # i ( feof # s h ) 1 0
}

// `file_read_chunk` below calls fread(buf, 1, n, h) directly into a
// Vec[u]'s data buffer; ferror gates the read-error path.
& `c` @ ferror s h → i32

// ── probe + mutation ───────────────────────────────────────────────
// access(2) / remove(3) / mkdir(2) / rmdir(2) wrappers. `access`
// uses F_OK (0) for "does this path exist at all". `mkdir` mode is
// 0755 (decimal 493).

& `c` @ remove s path → i32

& `c` @ mkdir s path i32 mode → i32

& `c` @ rmdir s path → i32

@ nurl_file_exists s path → i {
    ? == # i path 0 { ^ 0 } {}
    : i32 rc ( access path # i32 0 )
    ^ ? == # i rc 0 1 0
}

@ nurl_file_del s path → v {
    ? != 0 # i path { : i32 _ ( remove path ) } {}
}

@ nurl_dir_create s path → i {
    ? == # i path 0 { ^ -1 } {}
    : i32 rc ( mkdir path # i32 493 )
    ^ ? == # i rc 0 0 -1
}

@ nurl_dir_remove s path → i {
    ? == # i path 0 { ^ -1 } {}
    : i32 rc ( rmdir path )
    ^ ? == # i rc 0 0 -1
}

// mkdir one path component, treating an already-existing directory as
// success — the whole point of mkdir -p. errno-kind 2 is AlreadyExists.
@ __dir_create_step s p → !v IoErr {
    : i rc ( nurl_dir_create p )
    ? == rc 0 { ^ @ !v IoErr { T 0 } } {}
    : i k ( errno_kind )
    ? == k 2 { ^ @ !v IoErr { T 0 } } {}
    ^ @ !v IoErr { F ( __io_err_of_kind k ) }
}

// Create `path` and every missing parent directory. An existing leaf or
// parent is not an error. The first component that genuinely fails
// (permission denied, a file in the way) aborts and surfaces that error.
@ dir_create_all s path → !v IoErr {
    : i n ( nurl_str_len path )
    ? == n 0 { ^ @ !v IoErr { F @ IoErr { NotFound } } } {}
    : *u pb # *u path
    : String prefix ( string_new )
    : ~ i idx 0
    ~ < idx n {
        : i c & # i . pb idx 255
        ? | == c 47 == c 92 {
            // A separator: create everything accumulated so far. Skip a
            // leading or doubled separator (empty prefix → nothing yet).
            ? > ( string_len prefix ) 0 {
                ?? ( __dir_create_step ( string_data prefix ) ) {
                    T → {}
                    F e → {
                        ( string_free prefix )
                        ^ @ !v IoErr { F e }
                    }
                }
            } {}
        } {}
        ( string_push_char prefix c )
        = idx + idx 1
    }
    // Final component (the path itself, with no trailing separator).
    : !v IoErr last ( __dir_create_step ( string_data prefix ) )
    ( string_free prefix )
    ^ last
}

// unlink a non-directory entry, mapping errno to IoErr.
@ __unlink_entry s p → !v IoErr {
    : i32 rc ( unlink p )
    ? == rc 0 { ^ @ !v IoErr { T 0 } } {}
    ^ @ !v IoErr { F ( __io_err_of_kind ( errno_kind ) ) }
}

// Free a Vec[String] and every String it owns.
@ __fs_free_str_vec ( Vec String ) v → v {
    : ( @ v String ) drop_str \ String e → v { ( string_free e ) }
    ( vec_free_with [String] v drop_str )
}

// Recursively remove a directory and everything beneath it. Handed a
// plain file or a symlink, it unlinks that entry directly (rm -rf
// parity). Returns NotFound when `path` does not exist. On the first
// failure the walk stops and surfaces that error — entries already
// removed stay removed (best-effort, like rm -rf).
@ dir_remove_all s path → !v IoErr {
    : i t ( nurl_path_type path )
    ? == t 0 { ^ @ !v IoErr { F @ IoErr { NotFound } } } {}
    ? != t 2 { ^ ( __unlink_entry path ) } {}
    : !( Vec String ) IoErr lst ( dir_list path )
    ?? lst {
        F e → { ^ @ !v IoErr { F e } }
        T entries → {
            : i cnt ( vec_len [String] entries )
            : ~ i idx 0
            ~ < idx cnt {
                ?? ( vec_get [String] entries idx ) {
                    T name → {
                        : String full ( path_join path ( string_data name ) )
                        : s fp ( string_data full )
                        : !v IoErr r ? == 2 ( nurl_path_type fp ) { ( dir_remove_all fp ) } { ( __unlink_entry fp ) }
                        ( string_free full )
                        ?? r {
                            T → {}
                            F e → {
                                ( __fs_free_str_vec entries )
                                ^ @ !v IoErr { F e }
                            }
                        }
                    }
                    F → {}
                }
                = idx + idx 1
            }
            ( __fs_free_str_vec entries )
        }
    }
    // The directory is empty now — remove the directory itself.
    ^ ( dir_remove path )
}

// ── Handle-based streaming reads ────────────────────────────────────
//
// file_open + file_read_chunk read a file in fixed-size pieces, so an
// input far larger than RAM is processed without ever being fully
// resident. For line-oriented streaming use stdlib/std/bufio.nu, which
// adds a refill buffer and a memchr line scanner on top of the same
// FILE* handle; this layer is the raw binary primitive.
//
// File wraps a libc FILE* (an opaque `s`). file_open opens "rb"; the
// handle is closed by file_close.

: File { s raw }

@ file_open s path → !File IoErr {
    : *v h ( nurl_file_open path `rb` )
    ? == 0 # i h {
        ^ @ !File IoErr { F ( __io_err_of_kind ( errno_kind ) ) }
    } {}
    : s rawp # s h
    ^ @ !File IoErr { T @ File { rawp } }
}

// Read up to `n` bytes from the handle into an owned Vec[u]. A returned
// Vec shorter than `n` (down to empty) signals end of file — pair with
// file_eof for an explicit check. The caller owns the Vec (vec_free [u]).
@ file_read_chunk File f i n → !( Vec u ) IoErr {
    ? <= n 0 { ^ @ !( Vec u ) IoErr { T ( vec_new [u] ) } } {}
    : s hp . f raw
    ? == 0 # i hp {
        ^ @ !( Vec u ) IoErr { F @ IoErr { Other } }
    } {}
    : ( Vec u ) out ( vec_with_cap [u] n )
    : *u dst ( vec_data [u] out )
    : i got ( fread # s dst 1 n hp )
    ? & == got 0 != 0 # i ( ferror hp ) {
        ^ @ !( Vec u ) IoErr { F ( __io_err_of_kind ( errno_kind ) ) }
    } {}
    : b _ok ( vec_set_len [u] out got )
    ^ @ !( Vec u ) IoErr { T out }
}

@ file_eof File f → b {
    : s hp . f raw
    ^ != 0 ( nurl_file_eof # *v hp )
}

@ file_close File f → v {
    : s hp . f raw
    ? != 0 # i hp { ( nurl_file_close # *v hp ) } {}
}

// ── Rename / copy / tempfile (B6) ──────────────────────────────────

// libc rename(2): atomically move/rename within a filesystem (cross-
// filesystem moves fail with EXDEV — use fs_copy_file + file_delete).
& `c` @ rename s oldp s newp → i32

// libc mkstemp(3): the template's trailing "XXXXXX" is replaced in
// place with a unique suffix; creates the file 0600 and returns an
// open fd (or -1). We close the fd and hand back the path — callers
// write through the normal write_file* helpers.
& `c` @ mkstemp s template → i32

// Rename / move `from` to `to`. Atomic within a filesystem; an
// existing `to` is replaced (POSIX rename semantics). Cross-device
// moves surface as IoErr {Other} (EXDEV) — copy + delete instead.
@ fs_rename s from s to → !v IoErr {
    : i32 rc ( rename from to )
    ? == rc # i32 0 { ^ @ !v IoErr { T 0 } } {}
    ^ @ !v IoErr { F ( __io_err_of_kind ( errno_kind ) ) }
}

// Copy `src` to `dst` (truncating / creating `dst`). Streams in 64 KiB
// chunks through libc stdio so arbitrarily large files copy in bounded
// memory — never slurps the whole file. Does NOT preserve mode/mtime
// (a plain content copy); layer chmod on top if needed.
@ fs_copy_file s src s dst → !v IoErr {
    : s rf # s ( fopen src `rb` )
    ? == # i rf 0 { ^ @ !v IoErr { F ( __io_err_of_kind ( errno_kind ) ) } } {}
    : s wf # s ( fopen dst `wb` )
    ? == # i wf 0 {
        : i32 _rc ( fclose rf )
        ^ @ !v IoErr { F ( __io_err_of_kind ( errno_kind ) ) }
    } {}
    : i chunk 65536
    : ( Vec u ) buf ( vec_with_cap [u] chunk )
    : *u dp ( vec_data [u] buf )
    : ~ b ok T
    : ~ b going T
    ~ & going ok {
        : i got ( fread # s dp 1 chunk rf )
        ? > got 0 {
            : i put ( fwrite # s dp 1 got wf )
            ? != put got { = ok F } {}
        } {}
        ? < got chunk { = going F } {}
    }
    ( vec_free [u] buf )
    : i32 _wc ( fclose wf )
    : i32 _rc2 ( fclose rf )
    ? ok { ^ @ !v IoErr { T 0 } }
    { ^ @ !v IoErr { F @ IoErr { WriteFailed } } }
}

// Create a fresh, uniquely-named empty file under `dir` whose name
// begins with `prefix`, and return its path (owned String). `dir` ""
// defaults to ".". The file exists (0600) and is empty on return; the
// caller writes through write_file / append_file. Uses mkstemp, so the
// name cannot collide with a concurrent caller.
@ fs_tempfile s dir s prefix → !String IoErr {
    : s d ? == 0 ( nurl_str_len dir ) `.` dir
    : String tmpl ( string_with_cap + + ( nurl_str_len d ) ( nurl_str_len prefix ) 10 )
    ( string_push_str tmpl d )
    ( string_push_char tmpl 47 )  // '/'
    ( string_push_str tmpl prefix )
    ( string_push_str tmpl `XXXXXX` )
    : i32 fd ( mkstemp ( string_data tmpl ) )
    ? < # i fd 0 {
        ( string_free tmpl )
        ^ @ !String IoErr { F ( __io_err_of_kind ( errno_kind ) ) }
    } {}
    : i _c ( close # i fd )
    ^ @ !String IoErr { T tmpl }  // mkstemp filled XXXXXX in place
}

// ── Glob (B7) ──────────────────────────────────────────────────────
//
// fs_glob expands a shell-style path pattern against the filesystem:
//   *        any run of characters within one path segment (not '/')
//   ?        exactly one character (not '/')
//   [abc]    a character class; [a-z] ranges; [!...] / [^...] negation
//   **       (as a whole segment) zero or more directory levels
//
// A leading-dot name is matched only by a pattern segment that itself
// starts with '.' (the usual "glob hides dotfiles" rule). The pattern
// may be absolute ("/etc/*.conf") or relative ("src/**/*.nu"); relative
// results keep the pattern's own leading form. Returns an OWNED
// Vec[String] of matching paths, unsorted (sort_by cmp_string for a
// stable order). A pattern with no metacharacters yields the path iff
// it exists.

// Match one path SEGMENT `name` against glob segment `pat` (no '/').
@ __fnmatch_seg s pat s name → b {
    : i pn ( nurl_str_len pat )
    : i nn ( nurl_str_len name )
    // Dotfile rule: '*'/'?'/'[' never match a leading '.'.
    ? & > nn 0 == ( nurl_str_get name 0 ) 46 {
        ? & > pn 0 != ( nurl_str_get pat 0 ) 46 { ^ F } {}
    } {}
    ^ ( __fnmatch_at pat 0 pn name 0 nn )
}

// Recursive matcher over pat[pi..pn) vs name[ni..nn).
@ __fnmatch_at s pat i pi i pn s name i ni i nn → b {
    : ~ i p pi
    : ~ i k ni
    ~ < p pn {
        : i pc ( nurl_str_get pat p )
        ? == pc 42 {
            // '*' — collapse runs, then try every split (no '/' allowed).
            ~ & < p pn == ( nurl_str_get pat p ) 42 { = p + p 1 }
            ? >= p pn { ^ T } {}  // trailing '*' matches the rest
            : ~ i j k
            ~ <= j nn {
                ? ( __fnmatch_at pat p pn name j nn ) { ^ T } {}
                = j + j 1
            }
            ^ F
        } {
            ? >= k nn { ^ F } {}
            : i nc ( nurl_str_get name k )
            ? == pc 63 {
                = p + p 1 = k + k 1
            } {
                ? == pc 91 {
                    : i pe ( __fnmatch_class pat + p 1 pn nc )
                    ? < pe 0 { ^ F } {}  // no match / malformed
                    = p pe = k + k 1
                } {
                    ? == pc nc { = p + p 1 = k + k 1 } { ^ F }
                }
            }
        }
    }
    ^ == k nn
}

// Match a '[...]' class beginning at pat[start] (just past '['), against
// byte `c`. Returns the index just past the closing ']' on a match, or
// -1 on no-match / malformed (missing ']').
@ __fnmatch_class s pat i start i pn i c → i {
    : ~ i p start
    : ~ b neg F
    ? & < p pn | == ( nurl_str_get pat p ) 33 == ( nurl_str_get pat p ) 94 {
        = neg T = p + p 1
    } {}
    : ~ b hit F
    : ~ i first p
    ~ & < p pn ! & > p first == ( nurl_str_get pat p ) 93 {
        : i lo ( nurl_str_get pat p )
        // range "a-z" when a '-' with a following non-']' char
        ? & & < + p 2 pn == ( nurl_str_get pat + p 1 ) 45 != ( nurl_str_get pat + p 2 ) 93 {
            : i hi ( nurl_str_get pat + p 2 )
            ? & >= c lo <= c hi { = hit T } {}
            = p + p 3
        } {
            ? == c lo { = hit T } {}
            = p + p 1
        }
    }
    ? & < p pn == ( nurl_str_get pat p ) 93 {} { ^ -1 }  // unterminated class
    : b matched ? neg ! hit hit
    ? matched { ^ + p 1 } { ^ -1 }
}

// True iff `seg` contains a glob metacharacter (* ? [).
@ __glob_has_meta s seg → b {
    : i n ( nurl_str_len seg )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get seg k )
        ? | | == c 42 == c 63 == c 91 { ^ T } {}
        = k + k 1
    }
    ^ F
}

// Join `base` + '/' + `name` (base "" → just name; base "/" → "/name").
@ __glob_join s base s name → String {
    : i bn ( nurl_str_len base )
    : String out ( string_with_cap + + bn ( nurl_str_len name ) 2 )
    ? > bn 0 {
        ( string_push_str out base )
        ? != ( nurl_str_get base - bn 1 ) 47 { ( string_push_char out 47 ) } {}
    } {}
    ( string_push_str out name )
    ^ out
}

// Append every entry of directory `base` whose name matches `seg` to
// `acc`, as joined paths. `base` "" means the current directory. When
// `dirs_only` is true, keep only entries that are themselves
// directories (used for intermediate path segments).
@ __glob_expand_seg ( Vec String ) acc s base s seg b dirs_only → v {
    : s listdir ? == 0 ( nurl_str_len base ) `.` base
    : !( Vec String ) IoErr lr ( dir_list listdir )
    ?? lr {
        T entries → {
            : i ne ( vec_len [String] entries )
            : ~ i k 0
            ~ < k ne {
                : ?String eo ( vec_get [String] entries k )
                ?? eo {
                    T name → {
                        ? ( __fnmatch_seg seg ( string_data name ) ) {
                            : String full ( __glob_join base ( string_data name ) )
                            ? dirs_only {
                                ? == 2 ( nurl_path_type ( string_data full ) )
                                { ( vec_push [String] acc full ) }
                                { ( string_free full ) }
                            } {
                                ( vec_push [String] acc full )
                            }
                        } {}
                        ( string_free name )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free [String] entries )
        }
        F _ → {}  // unreadable dir → no matches from it
    }
}

// Collect `base` itself plus every descendant directory of `base`
// (recursive), for '**'. Pushes owned paths into `acc`.
@ __glob_walk_dirs ( Vec String ) acc s base → v {
    : s self ? == 0 ( nurl_str_len base ) `.` base
    ( vec_push [String] acc ( string_from base ) )
    : !( Vec String ) IoErr lr ( dir_list self )
    ?? lr {
        T entries → {
            : i ne ( vec_len [String] entries )
            : ~ i k 0
            ~ < k ne {
                : ?String eo ( vec_get [String] entries k )
                ?? eo {
                    T name → {
                        // '**' does not descend into dotfile dirs.
                        ? != ( nurl_str_get ( string_data name ) 0 ) 46 {
                            : String full ( __glob_join base ( string_data name ) )
                            ? == 2 ( nurl_path_type ( string_data full ) )
                            { ( __glob_walk_dirs acc ( string_data full ) ) } {}
                            ( string_free full )
                        } {}
                        ( string_free name )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free [String] entries )
        }
        F _ → {}
    }
}

// Split `pattern` into '/'-separated segments (owned Strings). A leading
// '/' yields a leading empty segment so the driver can seed an absolute
// base. Trailing/duplicate slashes collapse to empty segments which the
// driver skips.
@ __glob_split s pattern → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len pattern )
    : ~ i start 0
    : ~ i k 0
    ~ <= k n {
        ? | == k n == ( nurl_str_get pattern k ) 47 {
            : String seg ( string_with_cap + - k start 1 )
            : ~ i j start
            ~ < j k { ( string_push_char seg ( nurl_str_get pattern j ) ) = j + j 1 }
            ( vec_push [String] out seg )
            = start + k 1
        } {}
        = k + k 1
    }
    ^ out
}

@ fs_glob s pattern → !( Vec String ) IoErr {
    : ( Vec String ) segs ( __glob_split pattern )
    : i nseg ( vec_len [String] segs )
    // Frontier of currently-matched base paths. Seed: "" (relative) or
    // "/" when the pattern is absolute (first segment empty).
    : ~ ( Vec String ) frontier ( vec_new [String] )
    : ~ i first_seg 0
    : b absolute ? > nseg 0 {
        : ?String s0 ( vec_get [String] segs 0 )
        ?? s0 { T s → == 0 ( nurl_str_len ( string_data s ) ) F _ → F }
    } F
    ? absolute {
        ( vec_push [String] frontier ( string_from `/` ) )
        = first_seg 1
    } {
        ( vec_push [String] frontier ( string_from `` ) )
    }
    : ~ i si first_seg
    ~ < si nseg {
        : ?String seo ( vec_get [String] segs si )
        : s seg ?? seo { T s → ( string_data s ) F _ → `` }
        : b is_last == si - nseg 1
        // skip empty segments (collapsed slashes)
        ? == 0 ( nurl_str_len seg ) { = si + si 1 } {
            : ( Vec String ) next ( vec_new [String] )
            : i nf ( vec_len [String] frontier )
            : ~ i fi 0
            ~ < fi nf {
                : ?String bo ( vec_get [String] frontier fi )
                : s base ?? bo { T b → ( string_data b ) F _ → `` }
                ? & == ( nurl_str_get seg 0 ) 42 & == ( nurl_str_get seg 1 ) 42 == ( nurl_str_len seg ) 2 {
                    // '**' — base + all descendant dirs
                    ( __glob_walk_dirs next base )
                } {
                    ? ( __glob_has_meta seg ) {
                        ( __glob_expand_seg next base seg ! is_last )
                    } {
                        // literal segment: extend if the path exists
                        : String full ( __glob_join base seg )
                        : i ty ( nurl_path_type ( string_data full ) )
                        ? | & is_last > ty 0 & ! is_last == ty 2
                        { ( vec_push [String] next full ) }
                        { ( string_free full ) }
                    }
                }
                = fi + fi 1
            }
            ( __glob_free_vec frontier )
            = frontier next
            = si + si 1
        }
    }
    ( __glob_free_vec segs )
    ^ @ !( Vec String ) IoErr { T frontier }
}

// Free an owned Vec[String] (elements + container).
@ __glob_free_vec ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        : ?String eo ( vec_get [String] v k )
        ?? eo { T s → ( string_free s ) F _ → {} }
        = k + k 1
    }
    ( vec_free [String] v )
}
