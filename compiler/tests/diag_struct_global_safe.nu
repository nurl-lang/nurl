// A mutable global of a plain struct owns nothing, but no single atomic
// access covers it: a read racing a write elsewhere sees half of each. Only
// `unsafe` code reaches it.
$ `stdlib/core/io.nu`

: Pair { i a i b }

: ~ Pair g_pair 0

@ peek → i { ^ . g_pair a }

@ poke i v → v { = g_pair @ Pair { v v } }

unsafe @ main → i { ^ ( peek ) }
