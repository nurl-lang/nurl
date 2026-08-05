// unikernel/demos/initfs.nu — a file on a machine with no disk.
//
// The image carries a tar; `fopen` finds it there. Nothing in this
// program knows that: it is the same `fs_read_file` a Linux build
// would call, over the same `fopen`/`fread` nolibc already had.
//
// It also prints its arguments, which came from `args="…"` on the
// kernel command line — the B0 grammar, where the program's arguments
// are ONE key rather than the tail of the line, because QEMU appends
// its own device entries after -append and a program that read the
// tail would be handed them.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`

@ main → i {
    ( nurl_print `argc: ` ) ( nurl_print ( nurl_str_int ( nurl_argc ) ) ) ( nurl_print `\n` )
    : ~ i k 1
    ~ < k ( nurl_argc ) {
        ( nurl_print `arg: ` ) ( nurl_print ( nurl_argv k ) ) ( nurl_print `\n` )
        = k + k 1
    }
    ?? ( read_file `etc/greeting.txt` ) {
        T text → {
            ( nurl_print `file: ` )
            ( nurl_print ( string_data text ) )
            ( string_free text )
        }
        F _e → ( nurl_print `file: MISSING\n` )
    }
    ?? ( read_file `etc/absent.txt` ) {
        T t2 → { ( nurl_print `absent file read anyway\n` ) ( string_free t2 ) }
        F _e → ( nurl_print `a file that is not there: ENOENT\n` )
    }
    ^ 0
}
