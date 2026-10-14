// stdlib/std/mmap.nu — a file's bytes, mapped read-only.
//
//   ( file_map path )               → !MappedFile IoErr   the whole file
//   ( mapped_len MappedFile m )     → i
//   ( mapped_bytes MappedFile m )   → ( Slice u )   a checked view of the
//                                     bytes that lives no longer than `m`
//   ( mapped_ptr MappedFile m )     → *u   raw (spec §3.3e): the address,
//                                     for a zero-copy hand-off (a device
//                                     upload) whose caller keeps `m` alive
//
// Where the platform maps files (POSIX) the bytes are mmap'd PROT_READ /
// MAP_PRIVATE and paged in as they are read — opening a 10 GB model costs
// nothing until its tensors are touched. Elsewhere (wasm, win32) the file
// is read whole; the bytes are the same either way. The last owner of a
// MappedFile unmaps it. A mapping is read-only, so its copies may be
// shared between threads.
//
// What every model loader used to write by hand — open / lseek / mmap /
// munmap and peek-through-a-pointer reads — with the view the borrow
// checker can hold to the mapping's lifetime.

$ `stdlib/core/posix.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/arc.nu`

// `p` / `n`: the bytes. `mapped`: they are a mapping to unmap; otherwise
// they are `owned`'s.
raw : MappedFileImpl { * u p i n b mapped ( Vec u ) owned }

% Drop MappedFileImpl {
    unsafe @ drop MappedFileImpl x → v {
        ? . x mapped { : i32 _u ( munmap . x p . x n ) } {}
    }
}

: MappedFile { ( Arc MappedFileImpl ) a }

@ MappedFile_share MappedFile h → MappedFile { ^ @ MappedFile { ( arc_clone [MappedFileImpl] . h a ) } }

@ MappedFile_drop sink MappedFile h → v {}

// A file read whole: the MappedFile owns the bytes.
unsafe @ __mf_of_vec sink ( Vec u ) v → MappedFile {
    : *u p ( vec_data [u] v )
    : i n ( vec_len [u] v )
    ^ @ MappedFile { ( arc_new [MappedFileImpl] @ MappedFileImpl { p n F v } ) }
}

// Map the whole of `path` read-only (or read it, where the platform does
// not map files).
unsafe @ file_map s path → !MappedFile IoErr {
    ? == # i path 0 { ^ @ !MappedFile IoErr { F @ IoErr { Other } } } {}
    ? != ( posix_const `MAP_PRIVATE` ) -1 {
        : i32 fd ( open path # i32 ( posix_const `O_RDONLY` ) # i32 0 )
        ? < # i fd 0 { ^ @ !MappedFile IoErr { F ( _io_err_of_kind ( errno_kind ) ) } } {}
        : i sz ( lseek fd 0 # i32 2 )
        // an empty file has nothing to map (and mmap refuses length 0)
        ? <= sz 0 {
            : i32 _c ( close fd )
            ^ @ !MappedFile IoErr { T ( __mf_of_vec ( vec_new [u] ) ) }
        } {}
        : *u m ( mmap # *u 0 sz # i32 ( posix_const `PROT_READ` ) # i32 ( posix_const `MAP_PRIVATE` ) fd 0 )
        : i32 _c ( close fd )
        ? == # i m -1 { ^ @ !MappedFile IoErr { F @ IoErr { ReadFailed } } } {}
        ^ @ !MappedFile IoErr { T @ MappedFile { ( arc_new [MappedFileImpl] @ MappedFileImpl { m sz T ( vec_new [u] ) } ) } }
    } {}
    ?? ( read_file_bytes path ) {
        T data → { ^ @ !MappedFile IoErr { T ( __mf_of_vec data ) } }
        F e → { ^ @ !MappedFile IoErr { F e } }
    }
}

// The same over bytes already in memory (a test, a download): the
// MappedFile owns them.
@ mapped_of_bytes sink ( Vec u ) v → MappedFile { ^ ( __mf_of_vec v ) }

@ mapped_len MappedFile m → i { ^ . ( arc_get [MappedFileImpl] . m a ) n }

// The bytes as a checked view: it lives no longer than `m` (the borrow
// checker holds it to that), and every index is bounds-checked — a loop
// over a slice_window of it keeps its checks out of the loop.
unsafe @ mapped_bytes MappedFile m → ( Slice u ) {
    : MappedFileImpl x ( arc_get [MappedFileImpl] . m a )
    ^ ( slice_from_raw [u] . x p . x n )
}

// The address of the bytes, for a hand-off that takes a pointer (a device
// upload). raw: the caller keeps `m` alive while it is used.
raw @ mapped_ptr MappedFile m → *u { ^ . ( arc_get [MappedFileImpl] . m a ) p }
