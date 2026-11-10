// local_and_parameter_slices_joined_in_a_return: agora #545, #540 — `^ ? c loc p` and `^ ?? k { … }` over a local slice and a parameter: the join was one value with one answer, so either the parameter went back as the function's own (the caller freed its argument twice) or the local was lent (and leaked, or was freed under the caller).
// Closed: each arm of a returned join answers for itself: a local is handed over, a parameter copied, a fresh value handed over, and the function releases the local on the paths that did not return it.
// main (before this PR): AddressSanitizer, heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #545: a local slice and a parameter joined in a return were one owner short or one too many (double free, leak)
: | K { KA KB KC KD }

@ show [i a → v { ~ x a { ( nurl_println ( nurl_str_int x ) ) } }
@ mk → [i { ^ [i | 7 8] }

@ join b c [i p → [i {
    : [i loc [i | 1 2]
    ^ ? c loc p
}

@ pick K k [i p → [i {
    : [i loc [i | 1 2 3]
    ^ ?? k { KA → loc KB → p KC → [i | 4] KD → ( mk ) }
}

@ main → i {
    : [i q [i | 5 6]
    : [i j1 ( join T q )
    : [i j2 ( join F q )
    ( show j1 ) ( show j2 )
    : [i p1 ( pick @ K { KA } q )
    : [i p2 ( pick @ K { KB } q )
    : [i p3 ( pick @ K { KC } q )
    : [i p4 ( pick @ K { KD } q )
    ( show p1 ) ( show p2 ) ( show p3 ) ( show p4 )
    ( show q )
    ^ 0
}
