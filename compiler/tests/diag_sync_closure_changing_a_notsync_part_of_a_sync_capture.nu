// diag_sync_closure_changing_a_notsync_part_of_a_sync_capture.nu — a
// closure several threads run may not change a part of what it captured
// that the program marked `% NotSync`, whatever the capture's own mark
// says (Agora #719). `unsafe % Sync App {}` promises that a value of App
// orders every change made through it; `% NotSync ( W i ) {}` takes that
// back for the `( W i )` it holds. The rule asked the capture's type alone
// and excused the change, so eight threads grew one plain Vec (a double
// free). As everywhere, the negative mark outranks the positive. Refused,
// naming both marks.
$ `stdlib/std/arc.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: W [A] { ( Channel A ) c ( Vec A ) v }

@ wpush [A] ( W A ) w A x → v {
    ( vec_push [A] . w v x )
}

unsafe % Sync W {}

% NotSync ( W i ) {}

: App { ( W i ) wi ( W b ) wb }

unsafe % Sync App {}

: Holder { ( @ v i ) f i tag }

@ main → i {
    : App app @ App { @ ( W i ) { ( chan_new [i] ) ( vec_new [i] ) } @ ( W b ) { ( chan_new [b] ) ( vec_new [b] ) } }
    : ( @ v i ) work \ i k → v { ( wpush [i] . app wi k ) }
    : ( Arc Holder ) shared ( arc_new [Holder] @ Holder { work 7 } )
    ^ 0
}
