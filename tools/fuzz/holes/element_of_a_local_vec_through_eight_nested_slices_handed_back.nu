// element_of_a_local_vec_through_eight_nested_slices_handed_back: agora #754 — `^ ( slice_at [String] s8 0 )` inside 8 nested `?? ( slice_sub [String] s… 0 1 )` payloads over `( slice_from_vec [String] v )`, v a local Vec: past eight links the chain answered "not lent out of a local"
// Closed: a root that is itself a lend is followed down to what it was lent out of with no depth budget — each root asked once per question, its answer kept (__pl_chain_sub; agora #754).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #754: `^ ( slice_at [String] s8 0 )` inside 8 nested `?? ( slice_sub [String] s… 0 1 )` payloads over `( slice_from_vec [String] v )`, v a local Vec: past eight links the chain answered "not lent out of a local"
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ g → String {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element long enough to live on the heap for sure` ) )
    : ( Slice String ) s0 ( slice_from_vec [String] v )
    ?? ( slice_sub [String] s0 0 1 ) { T s1 → {
            ?? ( slice_sub [String] s1 0 1 ) { T s2 → {
                    ?? ( slice_sub [String] s2 0 1 ) { T s3 → {
                            ?? ( slice_sub [String] s3 0 1 ) { T s4 → {
                                    ?? ( slice_sub [String] s4 0 1 ) { T s5 → {
                                            ?? ( slice_sub [String] s5 0 1 ) { T s6 → {
                                                    ?? ( slice_sub [String] s6 0 1 ) { T s7 → {
                                                            ?? ( slice_sub [String] s7 0 1 ) { T s8 → {
                                                                    ^ ( slice_at [String] s8 0 )
                                                                } F → {} }
                                                        } F → {} }
                                                } F → {} }
                                        } F → {} }
                                } F → {} }
                        } F → {} }
                } F → {} }
        } F → {} }
    ^ ( string_from `none` )
}

@ main → i { : String r ( g ) ( nurl_println ( string_data r ) ) ^ 0 }
