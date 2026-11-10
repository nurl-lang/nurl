// A value nothing names — a call's result, a literal, a field taken out of
// either — read through with `.`: an element, a length, a field, a `~` loop
// over a field. The read releases the temporary where it is done with it,
// or gives it an owner for the rest of the scope where what it read is
// still inside. Each of these leaked the temporary (agora #545); a field of
// a `% Drop` temporary read in a loop body was released twice.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: H { [i items i n }
: HN { String name i n }
: HS { [String names i n }
: HV { ( Vec String ) names i n }
: R { String name i n }
: Row { [String cells i n }
: Tab { [Row rows i n }

% Drop R { @ drop R r → v { ( nurl_println `drop R` ) } }

@ mki → [i { ^ [i | 1 2 3] }
@ mks → [String { ^ [String | ( string_from `a long enough string to be on the heap, one` ) ( string_from `a long enough string to be on the heap, two!` )] }
@ mkh → H { ^ @ H { [i | 1 2 3] 7 } }
@ mkhs → HS { ^ @ HS { [String | ( string_from `a long enough string to be on the heap, one` ) ( string_from `a long enough string to be on the heap, two!` )] 7 } }
@ mkr → R { ^ @ R { ( string_from `a long enough string to be on the heap, r` ) 7 } }
@ mkstr → String { ^ ( string_from `a long enough string to be on the heap, made` ) }

@ mkhv → HV {
    : ~ ( Vec String ) w ( vec_new [String] )
    ( vec_push [String] w ( string_from `a long enough string to be on the heap, v1` ) )
    ( vec_push [String] w ( string_from `a long enough string to be on the heap, v2!` ) )
    ^ @ HV { w 2 }
}

@ mkt → Tab {
    ^ @ Tab { [Row | @ Row { [String | ( string_from `a long enough string to be on the heap, c1` ) ( string_from `a long enough string to be on the heap, c2!` )] 1 } @ Row { [String | ( string_from `a long enough string to be on the heap, c3!!` )] 2 }] 7 }
}

// An element and a length of a call's result.
@ elems → v {
    : i k 1
    : String x . ( mks ) k
    ( nurl_println ( string_data x ) )
    ( nurl_println ( string_data . ( mks ) k ) )
    ( nurl_println ( nurl_str_int . ( mki ) k ) )
    ( nurl_println ( nurl_str_int . ( mki ) length ) )
    ( nurl_println ( nurl_str_int . ( mks ) length ) )
}

// A literal read through.
@ literals String p [i q → v {
    ( nurl_println ( nurl_str_int . @ H { [i | 1 2 3] 7 } n ) )
    ( nurl_println ( nurl_str_int . @ HN { ( mkstr ) 8 } n ) )
    ( nurl_println ( nurl_str_int . . @ H { [i | 1 2 3] 7 } items length ) )
    ( nurl_println ( nurl_str_int . [String | ( mkstr )] length ) )
    : i z 0
    : String x . [String | ( mkstr )] z
    ( nurl_println ( string_data x ) )
    ( nurl_println ( nurl_str_int . [String | p] length ) )
    ( nurl_println ( nurl_str_int . @ HN { p 8 } n ) )
    ( nurl_println ( nurl_str_int . @ H { q 8 } n ) )
    ( nurl_println ( nurl_str_int ( string_len . @ HN { p 8 } name ) ) )
    ( nurl_println ( nurl_str_int . . @ H { q 8 } items length ) )
    : String a . @ HN { ( mkstr ) 8 } name
    ( nurl_println ( string_data a ) )
    : [i b . @ H { [i | 4 5 6] 8 } items
    ~ y b { ( nurl_println ( nurl_str_int y ) ) }
    : i w 1
    ( nurl_println ( nurl_str_int . . @ H { [i | 4 5 6] 8 } items w ) )
    ( nurl_println ( nurl_str_int . [i | 7 8 9] w ) )
}

// A field of a call's result, and what is in that field.
@ fields → v {
    : i k 1
    : i z 0
    ( nurl_println ( nurl_str_int . ( mkh ) n ) )
    ( nurl_println ( nurl_str_int . . ( mkh ) items length ) )
    ( nurl_println ( nurl_str_int . . ( mkh ) items k ) )
    ( nurl_println ( string_data . . ( mkhs ) names z ) )
    : String x . . ( mkhs ) names z
    ( nurl_println ( string_data x ) )
    ( nurl_println ( nurl_str_int . . ( mkhs ) names length ) )
}

// In a loop's condition and body, in the arms of a `?`, in a `^`.
@ in_loops → v {
    : ~ i k 0
    ~ < k . ( mki ) length { = k + k 1 }
    ( nurl_println ( nurl_str_int k ) )
    : ~ i z 0
    ~ < z . ( mks ) length {
        ( nurl_println ( string_data . ( mks ) z ) )
        ? > ( string_len . ( mks ) z ) 43 { ( nurl_println `long` ) } {}
        = z + z 1
    }
    : ~ i j 0
    ~ < j 2 {
        ( nurl_println ( string_data . ( mkr ) name ) )
        = j + j 1
    }
}

@ in_arms b c → i {
    ? c { ^ . ( mki ) length } {}
    : i n ? c . ( mki ) length . [i | 9] length
    ^ + + . ( mki ) length . [i | 1 2] length n
}

// A `~` loop over a field of a temporary; its element handed back, handed
// to a consumer, returned past a `;` defer.
@ walk → i {
    : ~ i t 0
    ~ x . ( mkhs ) names { = t + t ( string_len x ) }
    ~ x . ( mkhv ) names { = t + t ( string_len x ) }
    ~ r . ( mkt ) rows {
        ~ y . r cells { = t + t ( string_len y ) }
    }
    ^ t
}

@ first → String {
    ~ x . ( mkhs ) names { ^ x }
    ^ ( string_from `none` )
}

@ first_vec → String {
    ~ x . ( mkhv ) names { ^ x }
    ^ ( string_from `none` )
}

@ deferred → String {
    ; { ( nurl_println `bye` ) }
    ~ x . ( mkhs ) names { ^ x }
    ^ ( string_from `none` )
}

@ pick i k → String {
    ~ r . ( mkt ) rows {
        ~ x . r cells {
            ? == ( string_len x ) k { ^ x } {}
        }
    }
    ^ ( string_from `none` )
}

@ pickrow i k → Row {
    ~ r . ( mkt ) rows {
        ? == . r n k { ^ r } {}
    }
    ^ @ Row { [String | ( string_from `nothing found here, so a fresh one is made` )] 0 }
}

@ sinkit sink String q → i { ^ ( string_len q ) }

@ eat → i {
    : ~ i t 0
    ~ x . ( mkhs ) names { = t + t ( sinkit x ) }
    ~ x . ( mkhv ) names { = t + t ( sinkit x ) }
    ^ t
}

// A panic after the read: the unwind releases what the read kept.
@ boom i k → i { ? > k 0 { ( panic `boom` ) } {} ^ 5 }
@ work i k → i { : i z 0 : String x . ( mks ) z : i n ( boom k ) ^ + n ( string_len x ) }
@ work2 i k → i { ^ + . ( mks ) length ( boom k ) }

@ main → i {
    ( elems )
    : String p ( string_from `a long enough string to be on the heap, p` )
    : [i q [i | 1 2 3]
    ( literals p q )
    ( nurl_println ( string_data p ) )
    ( nurl_println ( nurl_str_int . q length ) )
    ( fields )
    ( in_loops )
    ( nurl_println ( nurl_str_int ( in_arms T ) ) )
    ( nurl_println ( nurl_str_int ( in_arms F ) ) )
    ( nurl_println ( nurl_str_int ( walk ) ) )
    : String a ( first )
    ( nurl_println ( string_data a ) )
    : String a2 ( first_vec )
    ( nurl_println ( string_data a2 ) )
    : String d ( deferred )
    ( nurl_println ( string_data d ) )
    : String e ( pick 43 )
    ( nurl_println ( string_data e ) )
    : String e2 ( pick 3 )
    ( nurl_println ( string_data e2 ) )
    : Row r ( pickrow 2 )
    ~ c . r cells { ( nurl_println ( string_data c ) ) }
    : Row r2 ( pickrow 9 )
    ~ c . r2 cells { ( nurl_println ( string_data c ) ) }
    ( nurl_println ( nurl_str_int ( eat ) ) )
    : !v PanicInfo pr ( recover \ → v { : i _q ( work 1 ) } )
    ?? pr {
        T u → { ( nurl_println `no panic` ) }
        F pe → { ( nurl_println `recovered` ) ( panic_info_free pe ) }
    }
    : !v PanicInfo pr2 ( recover \ → v { : i _q ( work2 1 ) } )
    ?? pr2 {
        T u → { ( nurl_println `no panic` ) }
        F pe → { ( nurl_println `recovered` ) ( panic_info_free pe ) }
    }
    ( nurl_println ( nurl_str_int ( work 0 ) ) )
    ( nurl_println ( nurl_str_int ( work2 0 ) ) )
    ^ 0
}
