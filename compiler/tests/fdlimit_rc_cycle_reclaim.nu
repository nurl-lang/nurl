// fdlimit_rc_cycle_reclaim.nu — the net under deterministic release: a
// file held by an unreachable Rc cycle the compiler cannot see a resource
// in (here behind a trait object, whose contents are not in its type) is
// released by the collector, which runs when an open fails for want of
// descriptors (EMFILE) — the open is then retried once. With the limit at
// 64, 300 such cycles each holding an open file used to fail at the 61st.
// Linux-only (setrlimit's RLIMIT_NOFILE numbering; compiler/tests/
// test_skips.sh).
$ `stdlib/std/rc.nu`
$ `stdlib/std/fs.nu`

& `c` @ setrlimit i32 res s lim → i32

%Named [T] { @ nm T self → i }

: Holder { File f }

% Named Holder { @ nm Holder h → i { ^ 1 } }

: Node { i id ? % Named obj ? ( Rc Node ) next }

@ cycle i k → b {
    ?? ( file_open `/etc/hostname` ) { T f → {
            : %Named o ( dyn Named @ Holder { f } )
            : ( Rc Node ) a ( rc_new [Node] @ Node { k @ ?% Named { F } @ ?( Rc Node ) { F } } )
            : ( Rc Node ) b ( rc_new [Node] @ Node { k @ ?% Named { T o } @ ?( Rc Node ) { T ( rc_clone [Node] a ) } } )
            ( rc_set [Node] a @ Node { k @ ?% Named { F } @ ?( Rc Node ) { T ( rc_clone [Node] b ) } } )
            ^ T
        } F e → { ^ F } }
}

@ main → i {
    // RLIMIT_NOFILE (7): soft and hard limit 64.
    : s lim ( nurl_alloc 16 )
    : *i lp # *i lim
    = . lp 0 64
    = . lp 1 64
    ? != 0 ( setrlimit 7 lim ) { ( nurl_print `setrlimit failed\n` ) ^ 1 } {}
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k 300 { = ok ( cycle k ) = k + k 1 }
    ? ok { ( nurl_print `300 cycles, each with an open file\n` ) } { ( nurl_print `open failed at ` ) ( nurl_print_int k ) ( nurl_print `\n` ) }
    ( nurl_free lim )
    ^ 0
}
