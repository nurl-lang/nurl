// stdlib/std/sort.nu — robust generic sort + binary search over Vec[A]
//
// API:
//   ( sort_by [A] v cmp )            → v   in-place sort
//   ( binary_search [A] v target cmp ) → ? i
//
// Implementation: introsort over a branchless Lomuto partition, the scheme
// Rust's sort_unstable (ipnsort) runs. A Hoare partition branches on every
// comparison, and on unordered data half of those branches are guessed
// wrong; the Lomuto loop below swaps every element unconditionally and
// only ADDS the comparison's outcome to an index, so it never branches on
// the data at all. Pivots are the median of three, or of three medians
// past 128 elements. Duplicates cannot drive it quadratic: a range whose
// pivot equals the pivot that bounds it from below (its "ancestor" — every
// element of the range is at least that one) is all-equal on the left of
// the pivot, so it is partitioned with the equal run on the left and that
// run is never looked at again. Ranges of up to 20 elements are
// insertion-sorted, and a recursion that runs out of its 2·log2(n) budget
// finishes with heapsort, so the worst case stays O(n log n). We recurse on
// the smaller side and loop on the larger, for O(log n) stack depth.
// The sort is not stable.

$ `stdlib/core/vec.nu`

// ── Internal helpers ───────────────────────────────────────────────

@ __sort_swap [A] * A data i i i j → v {
    : A a . data i
    : A b . data j
    = . data i b
    = . data j a
}

// The index, among a, b and c, of the median of their elements.
@ __sort_median3 [A] * A data i a i b i c ( @ i A A ) cmp → i {
    : b xy < ( cmp . data a . data b ) 0
    : b yz < ( cmp . data b . data c ) 0
    ? == xy yz { ^ b } {}
    : b xz < ( cmp . data a . data c ) 0
    ? == xy xz { ^ c } {}
    ^ a
}

// Partition data[lo+1 ..= hi] around the pivot at data[lo]. Afterwards the
// pivot is at the returned index p, everything before it compares below it
// (or, with `le`, not above it) and everything after it does not.
//
// Each element is swapped with the first one known to belong right of the
// pivot, and the boundary moves by the comparison's outcome — 0 or 1 — so
// the loop takes no branch that depends on the data.
@ __sort_partition [A] * A data i lo i hi b le ( @ i A A ) cmp → i {
    : A pivot . data lo
    : ~ i store + lo 1
    : ~ i k + lo 1
    ~ <= k hi {
        : A x . data k
        : i c ( cmp x pivot )
        : i left ? le ? <= c 0 1 0 ? < c 0 1 0
        = . data k . data store
        = . data store x
        = store + store left
        = k + k 1
    }
    : i p - store 1
    ( __sort_swap [A] data lo p )
    ^ p
}

// Hoare partition of data[lo..hi] around the median of its ends and middle.
// Sorting those three first leaves data[lo] ≤ pivot ≤ data[hi], so the two
// scans stop at the ends. Returns j with [lo..j] ≤ pivot ≤ [j+1..hi]. Its
// scans branch on every comparison, which costs nothing when the data is
// nearly in order and they all go the same way — the case __sort_qs sends
// here — and it swaps only what is out of place, so a nearly sorted range
// stays nearly sorted for the partitions below it.
@ __sort_hoare [A] * A data i lo i hi ( @ i A A ) cmp → i {
    : i pi + lo / - hi lo 2
    ? > ( cmp . data lo . data pi ) 0 { ( __sort_swap [A] data lo pi ) } {}
    ? > ( cmp . data lo . data hi ) 0 { ( __sort_swap [A] data lo hi ) } {}
    ? > ( cmp . data pi . data hi ) 0 { ( __sort_swap [A] data pi hi ) } {}
    : A pivot . data pi
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

// 1 when data[a] ≤ data[b], else 0.
@ __sort_le [A] * A data i a i b ( @ i A A ) cmp → i { ^ ? <= ( cmp . data a . data b ) 0 1 0 }

// Straight insertion sort over data[lo..hi] (inclusive). Quicksort hands off
// to this once a subrange is small: below the cutoff a partition's overhead
// costs more than a few shifts, and the branch-predictable inner loop wins
// on real data. Same comparator convention as the rest of the file: cmp a b
// > 0 ⇔ a > b, so this produces the identical ascending order as the
// quicksort path.
@ __sort_insertion [A] * A data i lo i hi ( @ i A A ) cmp → v {
    : ~ i i + lo 1
    ~ <= i hi {
        : A x . data i
        : ~ i j i
        ~ & > j lo > ( cmp . data - j 1 x ) 0 {
            = . data j . data - j 1
            = j - j 1
        }
        = . data j x
        = i + i 1
    }
}

// Cutoff below which insertion sort beats partitioning.
@ __SORT_INSERTION_CUTOFF → i { ^ 20 }

// Restore the max-heap property below `root` in the heap of `n` elements
// starting at data[base].
@ __sort_sift [A] * A data i base i root i n ( @ i A A ) cmp → v {
    : ~ i r root
    ~ T {
        : ~ i c + * r 2 1
        ? >= c n { ^ v } {}
        ? & < + c 1 n < ( cmp . data + base c . data + base + c 1 ) 0 { = c + c 1 } {}
        ? >= ( cmp . data + base r . data + base c ) 0 { ^ v } {}
        ( __sort_swap [A] data + base r + base c )
        = r c
    }
}

// Heapsort data[lo..hi] (inclusive): the fallback that keeps a partition
// sequence that keeps splitting badly at O(n log n).
@ __sort_heap [A] * A data i lo i hi ( @ i A A ) cmp → v {
    : i n + - hi lo 1
    : ~ i start - >> n 1 1
    ~ >= start 0 {
        ( __sort_sift [A] data lo start n cmp )
        = start - start 1
    }
    : ~ i end - n 1
    ~ > end 0 {
        ( __sort_swap [A] data lo + lo end )
        ( __sort_sift [A] data lo 0 end cmp )
        = end - end 1
    }
}

// Sort data[lo..hi] (inclusive). `anc` is the index of the pivot that
// bounds this range from below (every element here compares at least
// equal to it), -1 for none; `budget` is how many more partitions may
// split it before heapsort takes over.
@ __sort_qs [A] * A data i lo i hi i anc ( @ i A A ) cmp i budget → v {
    : ~ i l lo
    : ~ i h hi
    : ~ i a anc
    : ~ i bud budget
    ~ < l h {
        ? <= - h l ( __SORT_INSERTION_CUTOFF ) {
            ( __sort_insertion [A] data l h cmp )
            ^ v
        } {}
        ? <= bud 0 {
            ( __sort_heap [A] data l h cmp )
            ^ v
        } {}
        = bud - bud 1
        : i n + - h l 1
        : i mid + l >> n 1
        : i e >> n 3
        // Samples in order say the range is nearly sorted, and there the
        // branching Hoare partition is the fast one (see __sort_hoare):
        // three samples in order — 1 in 6 by chance on shuffled data — or,
        // past 128 elements, nine whose eight neighbouring pairs are all
        // in order but at most one, which tolerates a stray element and
        // happens by chance 1 in 720.
        : ~ b ordered == 2 + ( __sort_le [A] data l mid cmp ) ( __sort_le [A] data mid h cmp )
        ? > n 128 {
            : i q0 l
            : i q1 + l e
            : i q2 + l * e 2
            : i q3 - mid e
            : i q4 mid
            : i q5 + mid e
            : i q6 - h * e 2
            : i q7 - h e
            : i q8 h
            : i ups + + + ( __sort_le [A] data q0 q1 cmp ) ( __sort_le [A] data q1 q2 cmp ) ( __sort_le [A] data q2 q3 cmp ) ( __sort_le [A] data q3 q4 cmp )
            : i ups2 + + + ( __sort_le [A] data q4 q5 cmp ) ( __sort_le [A] data q5 q6 cmp ) ( __sort_le [A] data q6 q7 cmp ) ( __sort_le [A] data q7 q8 cmp )
            = ordered >= + ups ups2 7
        } {}
        ? ordered {
            : i j ( __sort_hoare [A] data l h cmp )
            ? < - j l - h j {
                ( __sort_qs [A] data l j -1 cmp bud )
                = l + j 1
            } {
                ( __sort_qs [A] data + j 1 h -1 cmp bud )
                = h j
            }
            // The Hoare split leaves no pivot in place to bound a side.
            = a -1
        } {
            : ~ i pi mid
            ? > n 128 {
                : i m1 ( __sort_median3 [A] data l + l e + l * e 2 cmp )
                : i m2 ( __sort_median3 [A] data - mid e mid + mid e cmp )
                : i m3 ( __sort_median3 [A] data - h * e 2 - h e h cmp )
                = pi ( __sort_median3 [A] data m1 m2 m3 cmp )
            } {
                = pi ( __sort_median3 [A] data l mid h cmp )
            }
            ( __sort_swap [A] data l pi )
            ? & >= a 0 >= ( cmp . data a . data l ) 0 {
                // The pivot equals the ancestor: everything not above it is
                // equal to it and already in place once moved left.
                : i p ( __sort_partition [A] data l h T cmp )
                = l + p 1
            } {
                : i p ( __sort_partition [A] data l h F cmp )
                ? < - p l - h p {
                    ( __sort_qs [A] data l - p 1 a cmp bud )
                    = l + p 1
                    = a p
                } {
                    ( __sort_qs [A] data + p 1 h p cmp bud )
                    = h - p 1
                }
            }
        }
    }
}

// ── Public API ─────────────────────────────────────────────────────

// The length of the run data[0..] starts with: ascending, or — reversed in
// place first, so it reads ascending too — strictly descending (strictly,
// so reversing it never swaps two equal elements past each other in a way
// a sort would not).
@ __sort_run [A] * A data i n ( @ i A A ) cmp → i {
    : ~ i k 2
    ? < ( cmp . data 1 . data 0 ) 0 {
        ~ & < k n < ( cmp . data k . data - k 1 ) 0 { = k + k 1 }
        : ~ i i 0
        : ~ i j - k 1
        ~ < i j { ( __sort_swap [A] data i j ) = i + i 1 = j - j 1 }
        ^ k
    } {}
    ~ & < k n >= ( cmp . data k . data - k 1 ) 0 { = k + k 1 }
    ^ k
}

// data[0..run) and data[run..n) are each sorted: merge them, from the back,
// through a copy of the shorter right part — O(n), and the right part is
// the one appended to a sorted Vec before it is sorted again.
@ __sort_merge_tail [A] * A data i run i n ( @ i A A ) cmp → v {
    : i t - n run
    : s buf ( nurl_alloc ( alloc_size Z A t ) )
    : *A bp # *A buf
    ( nurl_memcpy buf # s + # i data * run Z A * t Z A )
    : ~ i i - run 1
    : ~ i j - t 1
    : ~ i k - n 1
    ~ >= j 0 {
        ? & >= i 0 > ( cmp . data i . bp j ) 0 {
            = . data k . data i
            = i - i 1
        } {
            = . data k . bp j
            = j - j 1
        }
        = k - k 1
    }
    ( nurl_free buf )
}

@ sort_by [A] ( Vec A ) v ( @ i A A ) cmp → v {
    : i n ( vec_len [A] v )
    ? > n 1 {
        : *A data ( vec_data [A] v )
        : i run ( __sort_run [A] data n cmp )
        ? >= run n { ^ } {}
        // 2·floor(log2 n) partitions deep before heapsort.
        : ~ i budget 0
        : ~ i m n
        ~ > m 1 { = m >> m 1 = budget + budget 2 }
        // A sorted Vec with elements appended: sort the tail alone, merge.
        ? & > n 64 >= * run 2 n {
            ( __sort_qs [A] data run - n 1 -1 cmp budget )
            ( __sort_merge_tail [A] data run n cmp )
            ^
        } {}
        ( __sort_qs [A] data 0 - n 1 -1 cmp budget )
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
