// mem_dup_join_arms.nu — a `( mem_dup x )` as an arm of a `?` value join
// owns the copy it made (Agora #688): returned, bound, handed to a sink,
// pushed, beside a fresh call or beside the binding it copies, nested, in
// a loop and in a generic. Each copy is released once — by whoever the
// join handed it to, or at the arm's end when the other arm was chosen —
// so the sanitizer run shows no leak and no double free.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ eat sink S s → i { ^ . s n }

@ pick S a S b2 b c → S { ^ ? c ( mem_dup a ) ( mem_dup b2 ) }

@ pick3 S a S b2 i k → S { ^ ? == k 0 ( mem_dup a ) ? == k 1 ( mem_dup b2 ) ( mks `third string long enough for a heap buffer` ) }

@ picks ( Vec String ) v b c → String { ^ ? c ( mem_dup ( vec_at [String] v 0 ) ) ( mem_dup ( vec_at [String] v 1 ) ) }

@ gpick [T] T a T b2 b c → T { ^ ? c ( mem_dup a ) ( mem_dup b2 ) }

@ main → i {
    : S x ( mks `an element string long enough for a heap buffer` )
    : S y ( mks `another element string long enough for the heap` )
    : S e ( pick x y T )
    : S e2 ( pick x y F )
    ( nurl_println ( string_data . e name ) )
    ( nurl_println ( string_data . e2 name ) )
    : S t0 ( pick3 x y 0 ) : S t1 ( pick3 x y 1 ) : S t2 ( pick3 x y 2 )
    ( nurl_println_int + + . t0 n . t1 n . t2 n )
    : b c == . x n 1
    : S x2 ( mks `a binding the join below copies or takes, long enough` )
    : S own ? c ( mem_dup x2 ) x2
    : S x3 ( mks `a binding the join below takes or copies, long enough` )
    : S lent ? ! c ( mem_dup x3 ) x3
    ( nurl_println_int + . own n . lent n )
    ( nurl_println_int ( eat ? c ( mem_dup x ) ( mks `fresh one long enough for the heap buffer` ) ) )
    : ~ ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va ? c ( mem_dup x ) ( mks `pushed fresh long enough for the heap` ) )
    ( vec_push [S] va ? ! c ( mem_dup x ) ( mks `pushed fresh long enough for the heap` ) )
    : S fromv ? c ( mem_dup ( vec_at [S] va 0 ) ) ( mem_dup ( vec_at [S] va 1 ) )
    ( nurl_println_int + ( vec_len [S] va ) . fromv n )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 20 {
        : S r ? == % k 2 0 ( mem_dup x ) ( mks `loop fresh string long enough for heap` )
        = acc + acc . r n
        = k + k 1
    }
    ( nurl_println_int acc )
    : ~ ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `first string element, long enough for the heap` ) )
    ( vec_push [String] vs ( string_from `second string element, long enough for the heap` ) )
    : String s1 ( picks vs T )
    : String s2 ( picks vs F )
    ( nurl_println ( string_data s1 ) )
    ( nurl_println ( string_data s2 ) )
    : S g ( gpick [S] x y F )
    : String gs ( gpick [String] s1 s2 T )
    ( nurl_println ( string_data . g name ) )
    ( nurl_println ( string_data gs ) )
    ^ 0
}
