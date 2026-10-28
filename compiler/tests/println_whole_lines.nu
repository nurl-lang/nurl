// println_whole_lines.nu — a line printed on one thread is never split by
// a line from another. nurl_println writes its text and its newline under
// one hold of the output lock (stdout's FILE lock; runtime_core.c,
// NURL_IO_LOCK), and the capture buffer grows under the same hold.
//
// Eight fibers on four workers print 500 lines each into the capture
// buffer. Every line comes back whole: the 4000 lines are the same text,
// so the capture equals that text repeated. Before, libc's lock covered
// one call each — text, text, newline, newline was possible — and two
// workers could grow the capture buffer at once.

$ `stdlib/std/async.nu`
$ `stdlib/core/string.nu`

@ talk → v {
    : ~ i k 0
    ~ < k 500 { ( nurl_println `a whole line` ) = k + k 1 }
}

@ main → i {
    ( runtime_init 4 )
    ( nurl_print_buf_start )
    : ~ i f 0
    ~ < f 8 { ( spawn \ → v { ( talk ) } ) = f + f 1 }
    ( runtime_run )
    : s out ( nurl_print_buf_stop )
    ( runtime_shutdown )
    : String want ( string_new )
    : ~ i k 0
    ~ < k 4000 { ( string_push_str want `a whole line\n` ) = k + k 1 }
    ? ( nurl_str_eq out ( string_data want ) ) { ( nurl_println `4000 whole lines` ) } { ( nurl_println `a line was split` ) }
    ^ 0
}
