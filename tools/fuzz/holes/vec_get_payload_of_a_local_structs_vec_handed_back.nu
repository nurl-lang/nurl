// vec_get_payload_of_a_local_structs_vec_handed_back: `^ e` out of `( vec_get [String] . h items 0 )`, h a local struct: the field path `h.items` was no root that owns its value, so the element went to the caller as its own and was not taken out of its slot, and h's drop freed it under the caller.
// Closed: a field path is judged by the binding it is a field of (__mem_payload_local_lend1, mem_local_lend_of): a local struct that owns its fields lends what its Vec holds, and the payload handed on is taken out of its slot (agora #550).
// main 9093d6e3: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #550: a vec_get payload of a local struct's Vec handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) items i n }

@ pick → String {
    : H h @ H { ( vec_new [String] ) 0 }
    ( vec_push [String] . h items ( string_from `the first element of vs long enough for the heap allocation` ) )
    : ?String o ( vec_get [String] . h items 0 )
    ?? o { T e → { ^ e } F → {} }
    ^ ( string_from `none placeholder long enough for the heap allocation path yes` )
}

@ main → i { : String b ( pick ) ( nurl_println ( string_data b ) ) ^ 0 }
