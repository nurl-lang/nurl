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

// `raw` is either the malloc'd file contents (owned) or NULL on failure.
// Cast to i64 to detect NULL — calling nurl_str_len on NULL would crash.
@ read_file s path → !String IoErr {
    // mmap-backed read (fast path on POSIX) — kernel page-cache to
    // process address space without going through libc stdio's
    // buffered-i/o layer. ~20-40 ms faster than fread on warm-cache
    // 100 MB reads. Falls back to fread on WASI/MSVC.
    : s raw ( nurl_read_file_mmap path )
    : i p # i raw
    ? == p 0 {
        : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
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
@ write_file s path s content → !v IoErr {
    : i rc ( nurl_write_file_safe path content `wb` )
    ? == rc 0 {
        ^ @ !v IoErr { T 0 }
    } {}
    : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
    ^ @ !v IoErr { F e }
}

@ append_file s path s content → !v IoErr {
    : i rc ( nurl_write_file_safe path content `ab` )
    ? == rc 0 {
        ^ @ !v IoErr { T 0 }
    } {}
    : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
    ^ @ !v IoErr { F e }
}

@ file_exists s path → b {
    ^ != 0 ( nurl_file_exists path )
}

@ file_size s path → !i IoErr {
    : i n ( nurl_file_size path )
    ? < n 0 {
        : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
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
    : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
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
    : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
    ^ @ !v IoErr { F e }
}

// Remove an empty directory. Returns NotFound when missing, Other when
// the directory is non-empty (errno = ENOTEMPTY) — the errno-kind table
// folds the latter into Other rather than introducing a new variant.
@ dir_remove s path → !v IoErr {
    : i rc ( nurl_dir_remove path )
    ? == rc 0 {
        ^ @ !v IoErr { T 0 }
    } {}
    : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
    ^ @ !v IoErr { F e }
}

// List directory entries (excluding "." and "..") as owned Strings.
// The returned Vec is owned: free the elements first via vec_free_with
// + string_free, then drop the Vec itself. Order is platform-defined
// (POSIX returns the on-disk order; Windows returns FindFirstFile order).
// Callers that want a stable order should sort_by cmp_string afterwards.
@ dir_list s path → !( Vec String ) IoErr {
    : i h ( nurl_dir_list_open path )
    ? == h 0 {
        : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
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

@ read_file_bytes s path → !( Vec u ) IoErr {
    : s raw ( nurl_read_file_bytes path )
    : i p # i raw
    ? == p 0 {
        : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
        ^ @ !( Vec u ) IoErr { F e }
    } {}
    : i n ( nurl_last_bytes_len )
    : ( Vec u ) v ( vec_with_cap [u] n )
    : *u src # *u raw
    : ~ i k 0
    ~ < k n {
        ( vec_push [u] v . src k )
        = k + k 1
    }
    ( nurl_free raw )
    ^ @ !( Vec u ) IoErr { T v }
}

@ write_file_bytes s path ( Vec u ) v → !v IoErr {
    : i n ( vec_len [u] v )
    : *u data ( vec_data [u] v )
    : s raw # s data
    : i rc ( nurl_write_file_bytes path raw n `wb` )
    ? == rc 0 {
        ^ @ !v IoErr { T 0 }
    } {}
    : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
    ^ @ !v IoErr { F e }
}

@ append_file_bytes s path ( Vec u ) v → !v IoErr {
    : i n ( vec_len [u] v )
    : *u data ( vec_data [u] v )
    : s raw # s data
    : i rc ( nurl_write_file_bytes path raw n `ab` )
    ? == rc 0 {
        ^ @ !v IoErr { T 0 }
    } {}
    : IoErr e ( __io_err_of_kind ( nurl_errno_kind ) )
    ^ @ !v IoErr { F e }
}
