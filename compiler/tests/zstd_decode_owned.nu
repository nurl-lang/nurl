// zstd_decode_owned.nu — the Vec zstd_decode returns is the caller's.
//
// The decoder kept its output in a field of a hand-managed struct, and
// zstd_decode returned that field as read: a borrow. A caller that let
// the result go out of scope — the normal way since the memory model
// drops Vecs — leaked the whole decompressed output on every call; only
// a hand-written `vec_free` released it. The decoder now gives the buffer
// up (`mem_take`). Round-trips run for several rounds with no free by
// hand: the live allocation count must not grow.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/zstd.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ round → i {
    : ( Vec u ) src ( vec_new [u] )
    : ~ i k 0
    ~ < k 4000 { ( vec_push [u] src # u + 97 % * k 7 13 ) = k + k 1 }
    : ~ i total 0
    : ~ i r 0
    ~ < r 5 {
        : ( Vec u ) enc ( zstd_encode_at src 3 )
        ?? ( zstd_decode enc ) {
            T dec → { = total + total ( vec_len [u] dec ) }
            F _ → { = total - total 1 }
        }
        : ( Vec u ) dec2 ?? ( zstd_decode enc ) { T d → d F _ → ( vec_new [u] ) }
        = total + total ( vec_len [u] dec2 )
        = r + r 1
    }
    ^ total
}

@ main → i {
    : i r1 ( round )
    : i l1 ( live )
    : i r2 ( round )
    : i r3 ( round )
    : i l3 ( live )
    ( puts ( nurl_str_int r1 ) )
    ( puts ( nurl_str_int + r2 r3 ) )
    ? == l1 l3 { ( puts `live allocations: steady` ) } { ( puts ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l3 l1 ) ) ) }
    ^ 0
}
