// struct_global_torn_between_threads: a mutable global of a plain struct was read and written from safe code with ordinary (non-atomic) loads and stores; a thread writing it while another reads is a data race — the reader sees half of each write, and the program has undefined behaviour.
// Closed: a mutable global of a struct or an option is reached only from `unsafe` code, as one that owns something already was; scalar mutable globals are read and written with relaxed atomics instead (no race, same instructions on x86-64 and AArch64).
// main's compiler: compiled; the reader below could print a pair whose halves came from different writes.
// map: §6.5 | A3 | rejected | h272 | mutable struct global written/read by two threads non-atomically
$ `stdlib/core/io.nu`
$ `stdlib/std/thread.nu`

: Pair { i a i b }

: ~ Pair g_pair 0

@ main → i {
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 100000 { = g_pair @ Pair { k k } = k + k 1 } }
    : ~ i torn 0
    ?? ( thread_spawn_owned body ) {
        T t → {
            : ~ i k 0
            ~ < k 100000 { : Pair p g_pair ? != . p a . p b { = torn + torn 1 } {} = k + k 1 }
            : i _j ( thread_join t )
        }
        F _ → {}
    }
    ( nurl_println_int torn )
    ^ 0
}
