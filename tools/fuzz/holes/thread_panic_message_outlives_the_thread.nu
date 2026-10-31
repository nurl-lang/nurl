// thread_panic_message_outlives_the_thread: a panic's message is kept per thread until the next panic replaces it (what PanicInfo and nurl_panic_last_msg read), and a thread that ended kept its last one: every thread that ever recovered from a panic leaked its message.
// Closed: a thread that ends lets go of its last message (nurl__panic_thread_exit, next to the journal's own release).
// main (before this PR): LeakSanitizer reported one message per thread that had panicked.
// map: §7.2 | A2 | runs-clean | h293 | a thread's last panic message (kept for PanicInfo) was never released when the thread ended — leak per thread
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/panic.nu`

@ main → i {
    : ( Locked i ) caught ( locked_new [i] 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : !v PanicInfo pr ( recover \ → v { ( panic `a thread's own panic` ) } )
            ?? pr { T _ → {} F p → { ( locked_update [i] caught \ inout i n → v { = n + n 1 } ) ( panic_info_free p ) } }
        } )
        ?? r { T h → { ( vec_push [Thread] ts h ) } F _ → {} }
        = t + t 1
    }
    ~ h ts { ( thread_join h ) }
    ( nurl_print `caught: ` ) ( nurl_println_int ( locked_get [i] caught ) )
    ^ 0
}
