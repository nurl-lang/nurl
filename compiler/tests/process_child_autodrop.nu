// process_child_autodrop.nu — a spawned child is released by the language.
//
// A ProcChild keeps the runtime's child block in an rcbox: every copy — a
// struct field, a Vec element, a closure capture, `ProcChild_share` — is the
// same child, and its last owner closes the pipes, stops and reaps a child
// nobody waited for, and frees the block. Nothing below needs a `proc_free`
// (the one call is an early release of ONE owner: the child lives on in its
// copies). Every round must leave the live allocation count where it found
// it, and at the end no child may be left — running or unreaped. Before,
// each child leaked its block, and stayed a zombie or kept running, unless
// proc_free was called by hand, exactly once, on exactly one of its copies.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Holder { ProcChild ch i tag }

unsafe @ spawn1 s cmd s a0 → ProcChild {
    ?? ( process_spawn1 cmd a0 ) {
        T c → { ^ c }
        F e → {
            ( nurl_print `spawn-failed=` )
            ( nurl_println ( process_err_name e ) )
            ( nurl_exit 2 )
        }
    }
    ^ @ ProcChild { # s 0 }
}

@ line_len ProcChild p → i {
    ?? ( proc_read_line p 5000 ) {
        T s → { ^ ( string_len s ) }
        F → { ^ -1 }
    }
    ^ -1
}

@ make_reader ProcChild p → ( @ i ) {
    ^ \ → i { ^ ( line_len p ) }
}

@ one_round → i {
    : ~ i got 0
    // echo: its one line read, never waited — the drop reaps it.
    : ProcChild e ( spawn1 `echo` `hello` )
    = got + got ( line_len e )
    // cat: copies in a struct and a Vec; stdin left open, never waited.
    : ProcChild c ( spawn1 `cat` `-u` )
    : Holder h @ Holder { ( ProcChild_share c ) 1 }
    : ( Vec Holder ) hs ( vec_new [Holder] )
    ( vec_push [Holder] hs @ Holder { ( ProcChild_share c ) 2 } )
    ( vec_push [Holder] hs @ Holder { ( spawn1 `echo` `in-vec` ) 3 } )
    // An early release lets go of one owner; the copies keep the child.
    ( proc_free c )
    ( proc_write_line . h ch `round-trip` )
    ?? ( vec_get [Holder] hs 0 ) { T x → { = got + got ( line_len . x ch ) } F → {} }
    ( proc_write_line . h ch `again` )
    // A closure capturing the child reads through it.
    : ( @ i ) rd ( make_reader . h ch )
    = got + got ( rd )
    ?? ( vec_get [Holder] hs 1 ) { T x → { = got + got ( line_len . x ch ) } F → {} }
    // A waited child: the drop must not signal it again.
    : ProcChild w ( spawn1 `echo` `waited` )
    = got + got ( line_len w )
    = got + got * 100 ( proc_wait w )
    ^ got
}

// Windows always exports OS=Windows_NT; nothing else does.
@ is_windows → b {
    : ~ b w F
    ?? ( env_get `OS` ) {
        T e → { = w ( nurl_str_eq ( string_data e ) `Windows_NT` ) }
        F → {}
    }
    ^ w
}

unsafe @ main → i {
    // The children here are POSIX tools (echo, cat).
    ? ( is_windows ) { ( nurl_println `skip=posix-tools` ) ^ 0 } {}
    : ~ i v ( one_round )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 20 { = v ( one_round ) = k + k 1 }
    : i l1 ( live )
    ( nurl_println ( nurl_str_cat `line bytes ` ( nurl_str_int v ) ) )
    ( nurl_println ? == l0 l1 `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l1 l0 ) ) )
    // Every child is gone: none running, none left unreaped.
    : s st ( nurl_zalloc 4 )
    : i r ( waitpid -1 # *u st ( posix_const `WNOHANG` ) )
    ( nurl_free st )
    ( nurl_println ? < r 0 `children left: none` `children left: some` )
    ^ 0
}
