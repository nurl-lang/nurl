// enum_owner_given_back_its_own_value_through_a_forwarder: agora #450 — `: Sh e ( shfwdb o )  = o ( shfwd e )` for `Sh { Has ( Vec i ) Bare }`
// Closed: an enum's identity key is its ACTIVE variant's first payload slot that owns a heap buffer (null for a variant that owns nothing), not its first payload slot, which may hold a number another value holds too (mem_enum_variant_key; agora #450).
// main: heap-use-after-free (base 8452c536 too).
// map: §7.6 | A2 | runs-clean | - | agora #450: `: Sh e ( shfwdb o )  = o ( shfwd e )` for `Sh { Has ( Vec i ) Bare }`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ make3 → String { ^ ( string_from `a fresh string long enough for the heap, three` ) }

@ fwd String x → String { ^ x }

@ omake → ?String { ^ @ ?String { T ( make ) } }

@ ofwd ? String x → ?String { ^ x }

@ vfwd ( Vec i ) x → ( Vec i ) { ^ x }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

: N { String name i n }

@ nfwd N x → N { ^ x }

: | Sh { Has ( Vec i ) Bare }

@ shmk i v → Sh { : ~ ( Vec i ) xs ( vec_new [i] ) ( vec_push [i] xs v ) ^ @ Sh { Has xs } }

@ shfwd Sh x → Sh { ^ x }

@ main → i {
    : ~ Sh o ( shmk 5 )
    : Sh e ( shfwdb o )
    = o ( shfwd e )
    ?? o { Has xs → { ( nurl_println ( nurl_str_int ( vec_at [i] xs 0 ) ) ) } Bare → {} }
    ^ 0
}

@ shfwdb Sh x → Sh { ^ x }
