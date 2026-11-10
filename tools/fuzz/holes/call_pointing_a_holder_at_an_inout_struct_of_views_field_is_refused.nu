// call_pointing_a_holder_at_an_inout_struct_of_views_field_is_refused: `( f6 w . q vv )`, f6 copying `. src v` of its inout V (a struct of views) into its holder, `. q vv` viewing a String that ends before w is read
// Closed: an inout field with no storage of its own is the pair's source by its binding's path, not by `__last_member_root__` (another field's: gen_inout_field_addr publishes none) (agora #571, the review's finding).
// main c948ff15: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #571: `( f6 w . q vv )` with an inout struct-of-views field source
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: V { s v i n }
: Q { V vv s x ( Vec s ) vs W w }
: P { W w String s String t }

@ f6 inout W w inout V src → v { = w @ W { . src v } }

@ main → i {
    : ~ Q q @ Q { @ V { `lit` 0 } `lit` ( vec_new [s] ) @ W { `lit` } }
    : ~ W w @ W { `x` }
    {
        : String b ( string_from `the first heap string, long enough to be on the heap for sure` )
        = . q vv @ V { ( string_data b ) 1 }
        ( f6 w . q vv )
    }
    ( nurl_println . w v )
    ^ 0
}
