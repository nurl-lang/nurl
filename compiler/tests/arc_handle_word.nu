// A handle over an Arc kept in a module global as one word: arc_into_word
// gives the global an owner, a `# X w` cast reads it as a view (a one-word
// wrapper around a one-word handle takes the word at its innermost slot),
// arc_word_share makes another owner and arc_from_word takes the global's
// back. The counts go up and down exactly once each.
$ `stdlib/core/string.nu`
$ `stdlib/std/arc.nu`

: CounterImpl { i count }

: Counter { ( Arc CounterImpl ) a }

@ Counter_share Counter h → Counter { ^ @ Counter { ( arc_clone [CounterImpl] . h a ) } }

@ Counter_drop sink Counter h → v {}

: ~ i g_counter 0

unsafe @ keep Counter h → v { = g_counter ( arc_into_word [CounterImpl] ( arc_clone [CounterImpl] . h a ) ) }

unsafe @ peek → i {
    : Counter v # Counter g_counter
    ^ . ( arc_get [CounterImpl] . v a ) count
}

unsafe @ share → Counter { ^ @ Counter { ( arc_word_share [CounterImpl] g_counter ) } }

unsafe @ release → v {
    : Counter old @ Counter { ( arc_from_word [CounterImpl] g_counter ) }
    = g_counter 0
}

@ main → i {
    : Counter c @ Counter { ( arc_new [CounterImpl] @ CounterImpl { 41 } ) }
    ( nurl_println_int ( arc_strong [CounterImpl] . c a ) )
    ( keep c )
    ( nurl_println_int ( peek ) )
    : Counter s ( share )
    ( nurl_println_int ( arc_strong [CounterImpl] . s a ) )
    ( release )
    ( nurl_println_int ( arc_strong [CounterImpl] . s a ) )
    : Counter t s
    ( nurl_println_int ( arc_strong [CounterImpl] . t a ) )
    ^ 0
}
