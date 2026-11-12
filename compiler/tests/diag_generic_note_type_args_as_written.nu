// An error inside a generic instantiation is anchored in the template —
// at the template file's own column, with the file's own line echoed (the
// re-parsed body re-spaces its tokens and spells `B` as the instance's
// mangled `Rc__i64`: `par.nu:44:101` on an 87-byte line, `( ParOut
// Rc__i64 )` in the echo) — and a `note:` after it says which instance,
// its type arguments as the program writes them, and the line that asked
// for it: `note: in 'par_map_index [B = ( Rc i )]', instantiated here`
// (agora #751). The note is a `file:line:col:` line of its own, so an
// editor or an agent can jump to the call.
$ `stdlib/core/vec.nu`
$ `stdlib/std/par.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec ( Rc i ) ) r ( par_map_index [( Rc i )] 8 4 \ i k → ( Rc i ) { ^ ( rc_new [i] k ) } )
    ^ 0
}
