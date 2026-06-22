// btree_basic.nu — std/btree.nu acceptance: B-tree ordered map.
//
// 2000 integer keys inserted in LCG-scrambled order (forces node splits
// to depth ≥ 3 at t=8), full get/key_at verification, replace semantics,
// removal of every key (exercising the borrow/merge paths and root
// collapse), reinsertion after emptying, in-order traversal, and the
// owned-element free_with discipline with String keys/values.

$ `stdlib/core/string.nu`
$ `stdlib/std/btree.nu`

: i N 2000

@ main → i {
    : ( @ i i i ) cmp \ i a i b → i { ^ - a b }
    : ( BTree i i ) m ( btree_new [i i] )

    // ── scrambled insert: k = (i*1103515245 + 12345) mod N walk ──
    // visit each residue once via a full-period LCG over odd stride
    : ~ i k 0
    : ~ i ins_count 0
    ~ < k N {
        : i key % * + * k 7919 k 104729 N  // deterministic scramble, dupes possible
        : ?i prev ( btree_set [i i] m key * key 7 cmp )
        ?? prev { T _ → {} F _ → { = ins_count + ins_count 1 } }
        = k + k 1
    }
    // fill any residues the scramble missed (dupes replaced, not added)
    : ~ i k2 0
    ~ < k2 N {
        : ?i had ( btree_get [i i] m k2 cmp )
        ?? had { T _ → {} F _ → {
                : ?i p2 ( btree_set [i i] m k2 * k2 7 cmp )
                ?? p2 { T _ → {} F _ → { = ins_count + ins_count 1 } }
            } }
        = k2 + k2 1
    }
    ( nurl_print `len_after_fill=` ) ( nurl_print ( nurl_str_int ( btree_len [i i] m ) ) )
    ( nurl_print ` (expect ` ) ( nurl_print ( nurl_str_int N ) ) ( nurl_print `)\n` )

    // ── full get + key_at order-statistic check ──
    : ~ i bad_get 0
    : ~ i bad_at 0
    : ~ i j 0
    ~ < j N {
        : ?i g ( btree_get [i i] m j cmp )
        ?? g { T v → { ? != v * j 7 { = bad_get + bad_get 1 } {} } F _ → { = bad_get + bad_get 1 } }
        : ?i ka ( btree_key_at [i i] m j )
        ?? ka { T kk → { ? != kk j { = bad_at + bad_at 1 } {} } F _ → { = bad_at + bad_at 1 } }
        = j + j 1
    }
    ( nurl_print `bad_get=` ) ( nurl_print ( nurl_str_int bad_get ) )
    ( nurl_print ` bad_key_at=` ) ( nurl_print ( nurl_str_int bad_at ) ) ( nurl_print `\n` )

    // ── min/max + val_at ──
    ( nurl_print `min=` ) ?? ( btree_min_key [i i] m ) { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `none` ) }
    ( nurl_print ` max=` ) ?? ( btree_max_key [i i] m ) { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `none` ) }
    ( nurl_print ` val_at(500)=` ) ?? ( btree_val_at [i i] m 500 ) { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `none` ) }
    ( nurl_print `\n` )

    // ── replace returns Some(prev) ──
    : ?i rp ( btree_set [i i] m 1234 -1 cmp )
    ( nurl_print `replace_prev=` ) ?? rp { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `none` ) }
    ( nurl_print ` len_same=` ) ( nurl_print ? == ( btree_len [i i] m ) N `T` `F` ) ( nurl_print `\n` )
    : ?i _rb ( btree_set [i i] m 1234 * 1234 7 cmp )
    ?? _rb { T _ → {} F _ → {} }

    // ── remove every 3rd key (borrow/merge churn) ──
    : ~ i removed 0
    : ~ i r 0
    ~ < r N {
        : ?i out ( btree_remove [i i] m r cmp )
        ?? out { T v → { ? == v * r 7 { = removed + removed 1 } {} } F _ → {} }
        = r + r 3
    }
    ( nurl_print `removed_3rds=` ) ( nurl_print ( nurl_str_int removed ) )
    ( nurl_print ` len=` ) ( nurl_print ( nurl_str_int ( btree_len [i i] m ) ) ) ( nurl_print `\n` )

    // survivors intact, removed gone, order statistics still consistent
    : ~ i bad2 0
    : ~ i s 0
    ~ < s N {
        : ?i g2 ( btree_get [i i] m s cmp )
        : b should_have != 0 % s 3
        ?? g2 {
            T v → { ? | ! should_have != v * s 7 { = bad2 + bad2 1 } {} }
            F _ → { ? should_have { = bad2 + bad2 1 } {} }
        }
        = s + s 1
    }
    // key_at over the survivor sequence
    : ~ i want 1
    : ~ i ord 0
    : ~ i bad3 0
    ~ < want N {
        ? != 0 % want 3 {
            : ?i ka2 ( btree_key_at [i i] m ord )
            ?? ka2 { T kk → { ? != kk want { = bad3 + bad3 1 } {} } F _ → { = bad3 + bad3 1 } }
            = ord + ord 1
        } {}
        = want + want 1
    }
    ( nurl_print `bad_after_remove=` ) ( nurl_print ( nurl_str_int bad2 ) )
    ( nurl_print ` bad_keyat_after=` ) ( nurl_print ( nurl_str_int bad3 ) ) ( nurl_print `\n` )

    // ── in-order each: count + ascending check ──
    : s asc_state ( nurl_zalloc 24 )  // slot0 prev, slot1 count, slot2 ok
    ( nurl_poke asc_state 0 -1 )
    ( nurl_poke asc_state 2 1 )
    : ( @ v i i ) visit \ i kk i vv → v {
        ? <= kk ( nurl_peek asc_state 0 ) { ( nurl_poke asc_state 2 0 ) } {}
        ( nurl_poke asc_state 0 kk )
        ( nurl_poke asc_state 1 + ( nurl_peek asc_state 1 ) 1 )
    }
    ( btree_each [i i] m visit )
    ( nurl_print `each_count=` ) ( nurl_print ( nurl_str_int ( nurl_peek asc_state 1 ) ) )
    ( nurl_print ` ascending=` ) ( nurl_print ? == ( nurl_peek asc_state 2 ) 1 `T` `F` ) ( nurl_print `\n` )
    ( nurl_free asc_state )
    : *u visit_env # *u visit 1
    ( nurl_free # s visit_env )

    // ── drain to empty (root collapse) + reinsert ──
    : ~ i d 0
    ~ < d N {
        : ?i _o ( btree_remove [i i] m d cmp )
        ?? _o { T _ → {} F _ → {} }
        = d + d 1
    }
    ( nurl_print `drained: len=` ) ( nurl_print ( nurl_str_int ( btree_len [i i] m ) ) )
    ( nurl_print ` empty=` ) ( nurl_print ? ( btree_is_empty [i i] m ) `T` `F` )
    ( nurl_print ` min=` ) ?? ( btree_min_key [i i] m ) { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `none` ) }
    ( nurl_print `\n` )
    : ?i _ri ( btree_set [i i] m 42 99 cmp )
    ?? _ri { T _ → {} F _ → {} }
    ( nurl_print `reinsert: len=` ) ( nurl_print ( nurl_str_int ( btree_len [i i] m ) ) )
    ( nurl_print ` get42=` ) ?? ( btree_get [i i] m 42 cmp ) { T v → ( nurl_print ( nurl_str_int v ) ) F _ → ( nurl_print `none` ) }
    ( nurl_print `\n` )
    ( btree_free [i i] m )
    : *u cmp_env # *u cmp 1
    ( nurl_free # s cmp_env )

    // ── owned String keys+vals via free_with ──
    : ( @ i String String ) scmp \ String a String b → i { ^ ( nurl_str_cmp ( string_data a ) ( string_data b ) ) }
    : ( BTree String String ) sm ( btree_new [String String] )
    : ~ i t 0
    ~ < t 40 {
        : String key ( string_with_cap 8 )
        ( string_push_str key `k` )
        ( string_push_str key ( nurl_str_int + 100 t ) )
        : String val ( string_with_cap 8 )
        ( string_push_str val `v` )
        ( string_push_str val ( nurl_str_int t ) )
        : ?String pv ( btree_set [String String] sm key val scmp )
        ?? pv { T old → ( string_free old ) F _ → {} }
        = t + t 1
    }
    ( nurl_print `smap len=` ) ( nurl_print ( nurl_str_int ( btree_len [String String] sm ) ) )
    : String probe ( string_with_cap 8 )
    ( string_push_str probe `k123` )
    ( nurl_print ` get(k123)=` )
    ?? ( btree_get [String String] sm probe scmp ) { T v → ( nurl_print ( string_data v ) ) F _ → ( nurl_print `none` ) }
    ( nurl_print `\n` )
    ( string_free probe )
    : ( @ v String ) dk \ String x → v { ( string_free x ) }
    : ( @ v String ) dv \ String x → v { ( string_free x ) }
    ( btree_free_with [String String] sm dk dv )
    : *u scmp_env # *u scmp 1
    ( nurl_free # s scmp_env )
    : *u dk_env # *u dk 1
    ( nurl_free # s dk_env )
    : *u dv_env # *u dv 1
    ( nurl_free # s dv_env )
    ^ 0
}
