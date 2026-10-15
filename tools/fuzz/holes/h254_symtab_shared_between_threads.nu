// H254: a SymTab in an Arc reached two threads, and symtab_def changed the table from both with no lock.
// Closed: SymTab is `% NotSync`: it may move to another thread, never be reached from two.
// main's compiler: a data race on the table (ThreadSanitizer), and a lost or torn entry.
$ `stdlib/core/symtab.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Arc SymTab ) a ( arc_new [SymTab] ( symtab_new ) )
    : ( Arc SymTab ) b ( arc_clone [SymTab] a )
    : ( @ v ) body \ → v { ( symtab_def ( arc_get [SymTab] b ) `k` `v` ) }
    ?? ( thread_spawn body ) { T t → ( thread_join t ) F _ → {} }
    ( symtab_def ( arc_get [SymTab] a ) `j` `w` )
    ^ 0
}
