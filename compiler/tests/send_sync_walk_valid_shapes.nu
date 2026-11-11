// What the Send/Sync walk must keep accepting while it reads generic
// instances through their own fields and every type argument (agora #675,
// #683, #690, #693): generic structs of Send parts captured by a thread,
// shared in an Arc and sent on a Channel; options of Send types as type
// arguments; an ArcWeak of a payload an Arc may share; and the Sync instance
// of a generic beside a sibling marked NotSync.
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`
$ `stdlib/core/io.nu`

: Wrap [T] { ( Vec T ) items ( Arc T ) shared ? T maybe }
: Two [A B] { A first B second }

: W [A] { ( Channel A ) c ( Vec A ) v }

@ wsend [A] ( W A ) w A x → v { : b o ( chan_send [A] . w c x ) }

unsafe % Sync W {}

% NotSync ( W i ) {}

: App { ( W i ) wi ( W b ) wb }

unsafe % Sync App {}

@ main → i {
    : ( Wrap i ) w @ ( Wrap i ) { ( vec_new [i] ) ( arc_new [i] 7 ) @ ?i { T 3 } }
    : ( Two i ( Vec i ) ) p @ ( Two i ( Vec i ) ) { 2 ( vec_new [i] ) }
    : ( Arc ( Two i ( Wrap i ) ) ) both ( arc_new [( Two i ( Wrap i ) )] @ ( Two i ( Wrap i ) ) { 1 @ ( Wrap i ) { ( vec_new [i] ) ( arc_new [i] 8 ) @ ?i { F } } } )
    : ( Arc ( Two i ( Wrap i ) ) ) theirs ( arc_clone [( Two i ( Wrap i ) )] both )
    : ( Channel ( Wrap i ) ) ch ( chan_new [( Wrap i )] )
    : b sent ( chan_send [( Wrap i )] ch @ ( Wrap i ) { ( vec_new [i] ) ( arc_new [i] 9 ) @ ?i { F } } )
    : ( Vec ? String ) names ( vec_new [? String] )
    ( vec_push [? String] names @ ?String { T ( string_from `x` ) } )
    : ( Arc ( Locked ( Vec i ) ) ) la ( arc_new [( Locked ( Vec i ) )] ( locked_new [( Vec i )] ( vec_new [i] ) ) )
    : ( ArcWeak ( Locked ( Vec i ) ) ) lw ( arc_downgrade [( Locked ( Vec i ) )] la )
    : ( Arc App ) app ( arc_new [App] @ App { @ ( W i ) { ( chan_new [i] ) ( vec_new [i] ) } @ ( W b ) { ( chan_new [b] ) ( vec_new [b] ) } } )
    : ( Arc App ) app2 ( arc_clone [App] app )
    : ( Channel i ) out ( chan_new [i] )
    ?? ( thread_spawn \ → v {
        ( vec_push [i] . w items ( arc_get [i] . w shared ) )
        ( vec_push [i] . p second . p first )
        : i x . ( arc_get [( Two i ( Wrap i ) )] theirs ) first
        : ~ i got 0
        ?? ( chan_recv [( Wrap i )] ch ) {
            T m → { = got ( arc_get [i] . m shared ) }
            F → {}
        }
        ?? ( arc_weak_upgrade [( Locked ( Vec i ) )] lw ) {
            T up → { ( locked_update [( Vec i )] ( arc_get [( Locked ( Vec i ) )] up ) \ inout ( Vec i ) xs → v { ( vec_push [i] xs 1 ) } ) }
            F → {}
        }
        ( wsend [b] . ( arc_get [App] app2 ) wb T )
        : i total + + + ( vec_len [i] . w items ) ( vec_len [i] . p second ) + x got ( vec_len [? String] names )
        : b told ( chan_send [i] out total )
    } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ?? ( chan_recv [i] out ) {
        T total → { ( nurl_println ( nurl_str_int total ) ) }
        F → { ( nurl_println `no total` ) }
    }
    : i grown ( locked_apply [( Vec i ) i] ( arc_get [( Locked ( Vec i ) )] la ) \ inout ( Vec i ) xs → i { ^ ( vec_len [i] xs ) } )
    ( nurl_println ( nurl_str_int grown ) )
    ^ 0
}
