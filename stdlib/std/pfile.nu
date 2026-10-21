// stdlib/std/pfile.nu — a file read and written at offsets, from any thread.
//
// A `File` (stdlib/std/fs.nu) is a C stream: buffered, one direction per
// handle, and with ONE position that every read and write moves. Two
// threads sharing it — or one thread reading two places in turn — have to
// seek before each access, and a seek another thread makes in between
// lands their read in the wrong place. A database page file, a log, an
// index read by many threads needs the other shape: every access names
// its own offset (pread / pwrite), nothing is buffered behind the
// program's back, and the bytes go straight between the file and the
// program's own memory — a slice of a Vec the caller owns, a page frame,
// a window of a larger buffer — with no allocation per access.
//
//   ( pfile_open path mode )          → !PFile IoErr
//        PFILE_READ   read only; the file must exist
//        PFILE_RW     read and write; the file must exist
//        PFILE_CREATE read and write; created (empty) when absent
//        PFILE_TRUNC  read and write; created, or emptied when present
//   ( pfile_read_at f dst off )       → !i IoErr   up to slice_len dst
//                                      bytes into dst; fewer only at the
//                                      end of the file (0 there)
//   ( pfile_read_exact_at f dst off ) → !v IoErr   all of them, or
//                                      UnexpectedEof
//   ( pfile_write_at f src off )      → !v IoErr   all of src, or an error
//   ( pfile_read_vec_at f off n )     → !( Vec u ) IoErr   a fresh Vec of
//                                      up to n bytes
//   ( pfile_read_vec_into f out off n ) → !i IoErr   up to n bytes appended
//                                      to out (its spare capacity)
//   ( pfile_size f )                  → !i IoErr
//   ( pfile_set_len f n )             → !v IoErr   cut (or zero-extend)
//   ( pfile_sync f )                  → !v IoErr   data and metadata on
//                                      the device (fsync)
//   ( pfile_datasync f )              → !v IoErr   the data on the device
//                                      (fdatasync where there is one: the
//                                      write-ahead log's commit barrier)
//
// A PFile is a shared handle over one open descriptor: every copy is the
// same file, the last one closes it, and copies may be used from any
// number of threads at once — positional reads and writes never move a
// shared position (on Windows they are ReadFile / WriteFile at an
// offset, stdlib/runtime_core.c). What `pfile_read_at` fills is the
// slice it is handed, so it is a change to that storage: handing it a
// view a read guard or an Arc lends is a compile error (docs/MEMORY.md
// §6.5), and `pfile_write_at` only reads its slice. There is no early
// close: a descriptor closed while another thread still holds the handle
// could be reused by the next open and read there.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/core/marker.nu`
$ `stdlib/core/rcbox.nu`
$ `stdlib/std/fs.nu`

& `c` @ nurl_pread i32 fd *u buf i n i off → i

& `c` @ nurl_pwrite i32 fd in *u buf i n i off → i

& `c` @ nurl_fd_sync i32 fd → i

& `c` @ nurl_fd_datasync i32 fd → i

& `c` @ nurl_fd_truncate i32 fd i len → i

: i PFILE_READ 0
: i PFILE_RW 1
: i PFILE_CREATE 2
: i PFILE_TRUNC 3

// The descriptor: closed by the last owner.
: PFileImpl { i fd }

% Drop PFileImpl {
    @ drop PFileImpl x → v { ? >= . x fd 0 { : i32 _c ( close # i32 . x fd ) } {} }
}

: PFile { ( Shared PFileImpl ) ctl }

// Its drop closes a descriptor (stdlib/core/marker.nu).
% Resource PFile {}

// Positional reads and writes on one descriptor are safe from any thread.
% Send PFile {}

% Sync PFile {}

@ PFile_share PFile f → PFile { ^ @ PFile { ( shared_clone [PFileImpl] . f ctl ) } }

@ PFile_drop sink PFile f → v {}

@ __pfile_fd PFile f → i32 { ^ # i32 . ( shared_ptr [PFileImpl] . f ctl ) fd }

// The descriptor, for the stdlib's own transport layer (std/net.nu's
// tcp_sendfile hands it to sendfile(2)); the handle keeps it open.
@ _pfile_fd PFile f → i { ^ # i ( __pfile_fd f ) }

@ __pfile_err → IoErr { ^ ( _io_err_of_kind ( errno_kind ) ) }

@ pfile_open s path i mode → !PFile IoErr {
    : i rd ( posix_const `O_RDONLY` )
    : i rw ( posix_const `O_RDWR` )
    : i cr ( posix_const `O_CREAT` )
    : i tr ( posix_const `O_TRUNC` )
    : ~ i flags ? == mode PFILE_READ rd rw
    ? | == mode PFILE_CREATE == mode PFILE_TRUNC { = flags | flags cr } {}
    ? == mode PFILE_TRUNC { = flags | flags tr } {}
    // (No text mode: a byte read is the byte on the disk, on Windows too.)
    : i bin ( posix_const `O_BINARY` )
    ? > bin 0 { = flags | flags bin } {}
    : i32 fd ( open path # i32 flags # i32 420 )
    ? < # i fd 0 { ^ @ !PFile IoErr { F ( __pfile_err ) } } {}
    ^ @ !PFile IoErr { T @ PFile { ( shared_new [PFileImpl] @ PFileImpl { # i fd } ) } }
}

unsafe @ pfile_read_at PFile f ( Slice u ) dst i off → !i IoErr {
    : i n ( slice_len [u] dst )
    : *u p ( slice_data [u] dst )
    : ~ i got 0
    // A short read before the end is retried (a pipe, a signal): fewer
    // bytes than asked come back only at the end of the file.
    ~ < got n {
        : i r ( nurl_pread ( __pfile_fd f ) # *u + # i p got - n got + off got )
        ? < r 0 { ^ @ !i IoErr { F ( __pfile_err ) } } {}
        ? == r 0 { break } {}
        = got + got r
    }
    ^ @ !i IoErr { T got }
}

@ pfile_read_exact_at PFile f ( Slice u ) dst i off → !v IoErr {
    : i got \ ( pfile_read_at f dst off )
    ? < got ( slice_len [u] dst ) { ^ @ !v IoErr { F @ IoErr { UnexpectedEof } } } {}
    ^ @ !v IoErr { T 0 }
}

unsafe @ pfile_write_at PFile f ( Slice u ) src i off → !v IoErr {
    : i n ( slice_len [u] src )
    : *u p ( slice_data [u] src )
    : ~ i put 0
    ~ < put n {
        : i w ( nurl_pwrite ( __pfile_fd f ) # *u + # i p put - n put + off put )
        ? <= w 0 { ^ @ !v IoErr { F ? == w 0 @ IoErr { WriteFailed } ( __pfile_err ) } } {}
        = put + put w
    }
    ^ @ !v IoErr { T 0 }
}

@ pfile_read_vec_at PFile f i off i n → !( Vec u ) IoErr {
    : ( Vec u ) out ( vec_zeroed [u] n )
    : i got \ ( pfile_read_at f ( slice_from_vec [u] out ) off )
    : b _t ( vec_truncate [u] out got )
    ^ @ !( Vec u ) IoErr { T out }
}

// Up to `n` bytes at `off` appended to `out` — read straight into its
// spare capacity, so a caller streaming a file through one buffer
// allocates once. Ok(how many: fewer than `n` only at the end of the
// file, 0 there).
@ pfile_read_vec_into PFile f ( Vec u ) out i off i n → !i IoErr {
    ? <= n 0 { ^ @ !i IoErr { T 0 } } {}
    ( vec_reserve [u] out n )
    : i len ( vec_len [u] out )
    : *u p ( vec_data [u] out )
    : ~ i got 0
    ~ < got n {
        : i r ( nurl_pread ( __pfile_fd f ) # *u + # i p + len got - n got + off got )
        ? < r 0 { ^ @ !i IoErr { F ( __pfile_err ) } } {}
        ? == r 0 { break } {}
        = got + got r
    }
    : b _l ( vec_set_len [u] out + len got )
    ^ @ !i IoErr { T got }
}

@ pfile_size PFile f → !i IoErr {
    : FileStat st \ ( fs_fstat # i ( __pfile_fd f ) )
    ^ @ !i IoErr { T . st size }
}

@ pfile_set_len PFile f i n → !v IoErr {
    ? == 0 ( nurl_fd_truncate ( __pfile_fd f ) n ) { ^ @ !v IoErr { T 0 } } {}
    ^ @ !v IoErr { F ( __pfile_err ) }
}

@ pfile_sync PFile f → !v IoErr {
    ? == 0 ( nurl_fd_sync ( __pfile_fd f ) ) { ^ @ !v IoErr { T 0 } } {}
    ^ @ !v IoErr { F ( __pfile_err ) }
}

@ pfile_datasync PFile f → !v IoErr {
    ? == 0 ( nurl_fd_datasync ( __pfile_fd f ) ) { ^ @ !v IoErr { T 0 } } {}
    ^ @ !v IoErr { F ( __pfile_err ) }
}
