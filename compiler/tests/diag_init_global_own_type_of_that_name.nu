// diag_init_global_own_type_of_that_name.nu — what a global set at start
// may hold is the standard library's handles that synchronise themselves
// (a Locked, an Arc, a Channel, a Mutex, a Cond, a Semaphore), not a type
// that is spelled like one: a program that imports no std/arc may declare
// a generic struct of its own named `Arc`, and its name promises nothing
// about what two threads reading it do (agora #639).
$ `stdlib/std/rc.nu`

: Arc [T] { ( Rc T ) r }

@ make → ( Arc i ) { ^ @ ( Arc i ) { ( rc_new [i] 5 ) } }

: ( Arc i ) g_one ( make )

@ main → i { ^ - ( rc_strong [i] . g_one r ) 1 }
