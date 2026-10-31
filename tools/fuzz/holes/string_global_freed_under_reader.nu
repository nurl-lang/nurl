// string_global_freed_under_reader: a mutable string global took ownership of a fresh string in safe code (`= g_name ( nurl_str_cat … )`), and the next assignment freed it — while another thread was reading it. ASan: heap-use-after-free in strlen.
// Closed: safe code may not hand a global a string to own (the assignment is rejected); a mutable `s` global holds literals, text that changes at run time lives in a `( Locked String )` set at start, and an `unsafe` function may still store an owned string, vouching that nothing races on it.
// main's compiler: compiled; ASan reported heap-use-after-free within a few thousand iterations.
// map: §6.5 | A3 | rejected | h273 | string global reassigned (old freed) while another thread reads it
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`

: ~ s g_name `start`

@ main → i {
    : ( @ v ) body \ → v {
        : ~ i k 0
        ~ < k 200000 { = g_name ( nurl_str_cat `abc` `defghijklmnopqrstuvwxyz` ) = k + k 1 }
    }
    : ~ i tot 0
    ?? ( thread_spawn_owned body ) {
        T t → {
            : ~ i k 0
            ~ < k 200000 { = tot + tot ( nurl_str_len g_name ) = k + k 1 }
            : i _j ( thread_join t )
        }
        F _ → {}
    }
    ( nurl_println_int tot )
    ^ 0
}
