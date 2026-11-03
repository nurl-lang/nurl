// inout_enum_given_a_value_with_an_equal_scalar_key: agora #450 — an inout enum keyed on an equal scalar first payload given another parameter's value
// Closed: an enum's identity key is its ACTIVE variant's first payload slot that owns a heap buffer (null for a variant that owns nothing), not its first payload slot, which may hold a number another value holds too (mem_enum_variant_key; agora #450).
// main: heap-use-after-free (base 8452c536 too).
// map: §7.6 | A2 | runs-clean | - | agora #450: an inout enum keyed on an equal scalar first payload given another parameter's value
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

: | E { A i String B String }

@ ide E e → E { ^ e }

@ put inout E o E other → v { = o ( ide other ) }

@ show E e → v { ?? e { A n s → { ( nurl_println ( string_data s ) ) } B s → { ( nurl_println ( string_data s ) ) } } }

@ main → i {
    : ~ E a @ E { A 5 ( make ) }
    : E x @ E { A 5 ( make2 ) }
    ( put a x )
    ( show a )
    ( show x )
    ^ 0
}
