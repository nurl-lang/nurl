// qq_value_arm_holder_in_a_user_enum_match: agora #416 — a user enum `?? e { A → … B x → a C → … }` whose arm is a holder binding
// Closed: a `??` value's arm is taken by its operand, as a `?` arm is — a bare binding by its name, so what it holds and views goes with the join; a literal by none (agora #416).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #416: a user enum `?? e { A → … B x → a C → … }` whose arm is a holder binding
$ `stdlib/core/string.nu`

: W { s v }
: | E { A B i C }

@ main → i {
    : ~ W a @ W { `x` }
    : E e @ E { B 3 }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        = a @ W { ( string_data t ) }
        = a ?? e { A → @ W { `lit` } B x → a C → @ W { `other` } }
    }
    ( nurl_println . a v )
    ^ 0
}
