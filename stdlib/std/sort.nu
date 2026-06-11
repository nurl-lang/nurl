// stdlib/std/sort.nu — robust generic sort + binary search over Vec[A]
//
// API:
//   ( sort_by [A] v cmp )            → v   in-place sort
//   ( binary_search [A] v target cmp ) → ? i
//
// Implementation: in-place Quicksort using Hoare partitioning and
// median-of-three pivot selection. Hoare partitioning is significantly
// more robust than Lomuto when handling many identical elements (it
// splits duplicates roughly equally). We use the "recurse on smaller,
// loop on larger" optimization to guarantee O(log N) stack depth.

$ `stdlib/core/vec.nu`

// ── Internal helpers ───────────────────────────────────────────────

@ __sort_swap [A] * A data i i i j → v {
    : A a . data i
    : A b . data j
    = . data i b
    = . data j a
}

// Hoare partition: returns j such that [lo..j] <= pivot and [j+1..hi] >= pivot.
@ __sort_partition_hoare [A] * A data i lo i hi ( @ i A A ) cmp → i {
    // Median-of-three pivot selection
    : i mid + lo / - hi lo 2
    : A x_lo . data lo
    : A x_mid . data mid
    : A x_hi . data hi

    // Sort lo, mid, hi to pick median
    ? > ( cmp x_lo x_mid ) 0 { ( __sort_swap [A] data lo mid ) } {}
    : A x_lo2 . data lo
    ? > ( cmp x_lo2 x_hi ) 0 { ( __sort_swap [A] data lo hi ) } {}
    : A x_mid2 . data mid
    ? > ( cmp x_mid2 x_hi ) 0 { ( __sort_swap [A] data mid hi ) } {}

    // Pivot is now at mid
    : A pivot . data mid
    : ~ i i - lo 1
    : ~ i j + hi 1

    ~ T {
        = i + i 1
        ~ < ( cmp . data i pivot ) 0 { = i + i 1 }

        = j - j 1
        ~ > ( cmp . data j pivot ) 0 { = j - j 1 }

        ? >= i j { ^ j } {}
        ( __sort_swap [A] data i j )
    }
}

@ __sort_qs [A] * A data i lo i hi ( @ i A A ) cmp → v {
    : ~ i l lo
    : ~ i h hi
    ~ < l h {
        : i p ( __sort_partition_hoare [A] data l h cmp )
        // Guarantee O(log N) stack depth by recursing on the smaller partition
        // and looping on the larger one.
        ? < - p l - h p {
            ( __sort_qs [A] data l p cmp )
            = l + p 1
        } {
            ( __sort_qs [A] data + p 1 h cmp )
            = h p
        }
    }
}

// ── Public API ─────────────────────────────────────────────────────

@ sort_by [A] ( Vec A ) v ( @ i A A ) cmp → v {
    : i n ( vec_len [A] v )
    ? > n 1 {
        : *A data ( vec_data [A] v )
        ( __sort_qs [A] data 0 - n 1 cmp )
    } {}
}

@ binary_search [A] ( Vec A ) v A target ( @ i A A ) cmp → ?i {
    : i n ( vec_len [A] v )
    ? == n 0 { ^ @ ?i { F 0 } } {}
    : *A data ( vec_data [A] v )
    : ~ i lo 0
    : ~ i hi n
    ~ < lo hi {
        : i mid + lo / - hi lo 2
        : A x . data mid
        : i c ( cmp x target )
        ? == c 0 { ^ @ ?i { T mid } } {}
        ? < c 0 { = lo + mid 1 } { = hi mid }
    }
    ^ @ ?i { F 0 }
}
