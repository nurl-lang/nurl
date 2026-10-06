// value_arm_drops_binding.nu — a value-producing `??` arm that hands over
// an owned value still drops the payload it bound.
//
// `^ ?? ( read_file p ) { T text → { : ( Vec String ) v ( split … text ) v } … }`
// parked `text`'s drop for the join's verdict, and a consumed value kept
// every parked drop (the value might point into an arm-local). A value
// that is owned and holds no address cannot — `text` leaked on every call
// (packages/nurl-cov, wave-1 package sweep). A value that is a view of the
// payload still keeps it alive (`T text → ( string_data text )` is not
// owned, so nothing is dropped behind it).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ report s what i d → v { ( nurl_print what ) ( nurl_print_int d ) ( nurl_print `\n` ) }

@ get i k → !String i {
    : String s ( string_from `hello world` )
    ( string_push_int s k )
    ^ @ !String i { T s }
}

@ mkv s t → ( Vec i ) { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v ( nurl_str_len t ) ) ^ v }

@ tail_vec i k → ( Vec i ) {
    ^ ?? ( get k ) {
        T text → {
            : ( Vec i ) v ( mkv ( string_data text ) )
            v
        }
        F _ → ( vec_new [i] )
    }
}

@ tail_call i k → ( Vec i ) {
    ^ ?? ( get k ) {
        T text → ( mkv ( string_data text ) )
        F _ → ( vec_new [i] )
    }
}

@ tail_cond i k → String {
    ^ ? > k 5 ?? ( get k ) {
        T text → { : String c ( string_from ( string_data text ) ) c }
        F _ → ( string_from `` )
    } ( string_from `small` )
}

@ tail_self i k → String {
    ^ ?? ( get k ) {
        T text → text
        F _ → ( string_from `` )
    }
}

@ main → i {
    : ~ i k 0
    : ~ i l0 ( live )
    : ~ i acc 0
    = k 0 ~ < k 20 { : ( Vec i ) x ( tail_vec k ) = acc + acc ( vec_len [i] x ) = k + k 1 }
    ( report `arm block yields a Vec: ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { : ( Vec i ) x ( tail_call k ) = acc + acc ( vec_len [i] x ) = k + k 1 }
    ( report `arm yields a call: ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { : String x ( tail_cond k ) = acc + acc ( string_len x ) = k + k 1 }
    ( report `nested in ?: ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { : String x ( tail_self k ) = acc + acc ( string_len x ) = k + k 1 }
    ( report `arm yields its binding: ` - ( live ) l0 )
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ^ 0
}
