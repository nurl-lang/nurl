// vec_get_payload_returned_under_a_defer_that_reads_its_slot_runs_clean: agora #561 — `^ e` of a `vec_get` payload of a local Vec, with a defer armed before it that hands the slot's String to a C call: the defer runs while the Vec still holds the element
// main 6bafcaa1: the `^` took the element out of its slot before the chain, so the defer read an emptied String and nurl_str_cat copied from its null data (SEGV).
// map: §2.10 | A2 | runs-clean | - | agora #561: `^ e` of a `vec_get` payload of a local Vec, with a defer armed before it that hands the slot's String to a C call: the defer runs while the Vec still holds the element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ first → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `abc` ) )
    ; { ( nurl_println ( nurl_str_cat `got ` ( string_data ( vec_at [String] vs 0 ) ) ) ) }
    ?? ( vec_get [String] vs 0 ) { T e → { ^ e } F → { ^ ( string_new ) } }
}

@ main → i {
    : String r ( first )
    ( nurl_println ( string_data r ) )
    ^ 0
}
