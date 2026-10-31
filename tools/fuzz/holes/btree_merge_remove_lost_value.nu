// btree_merge_remove_lost_value: removing a key from a BTree inner node whose two neighbouring kids were both minimal lost the entry's value. The value was taken out of its slot first — which, since `mem_take` of a place zeroes it, left the slot empty — and the merge then moved that empty slot down; the removal below returned the empty value, and the real one leaked.
// Closed: the value leaves its slot only when a predecessor or successor fills it; on a merge the entry moves down whole and is removed (and returned) there.
// main (before this PR): LeakSanitizer reports every removed String whose key sat in an inner node at a merge.
// map: §6.4 | B | runs-clean | h210 | stdlib BTree remove-with-merge moves emptied slot down: value leaks
$ `stdlib/std/btree.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`

@ cmp i a i b → i { ^ ? < a b -1 ? > a b 1 0 }

@ val i k → String { : String s ( string_from `a value long enough for the heap ` ) ( string_push_int s k ) ^ s }

@ main → i {
    : ( BTree i String ) t ( btree_new [i String] )
    : ~ i k 0
    ~ < k 3000 { : ?String o ( btree_set [i String] t k ( val k ) \ i a i b → i { ^ ( cmp a b ) } ) = k + k 1 }
    = k 0
    : ~ i got 0
    ~ < k 3000 {
        : ?String r ( btree_remove [i String] t k \ i a i b → i { ^ ( cmp a b ) } )
        ? ( opt_is_some [String] r ) { = got + got 1 } {}
        = k + k 3
    }
    ? != got 1000 { ( nurl_print `lost values\n` ) ^ 1 }
    ^ 0
}
