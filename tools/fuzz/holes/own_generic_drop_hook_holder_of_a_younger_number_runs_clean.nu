// own_generic_drop_hook_holder_of_a_younger_number_runs_clean: AGORA-384 guard — a program's own generic handle with a drop hook, given a value declared after it that is only a number: nothing it holds is a view of the younger binding, accepted
// map: §7.6 | A2 | runs-clean | - | AGORA-384 guard: a younger binding copied into a hook-owning holder as a number
$ `stdlib/core/string.nu`

: Holder [T] { s name T x }

@ Holder_drop [T] sink ( Holder T ) h → v { ( nurl_println . h name ) }

@ main → i {
    : ~ ( Holder i ) h @ ( Holder i ) { `literal` 1 }
    : i k 41
    = h @ ( Holder i ) { `another literal` k }
    ^ 0
}
