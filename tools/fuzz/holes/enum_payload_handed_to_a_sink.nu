// enum_payload_handed_to_a_sink: a match arm's payload of an enum the program still holds — `?? s { Has t → { ( consume t ) } … }`, `consume` taking a `sink String` — went to the `sink` as is: the callee released it, and the enum released it again when it was dropped. A `% Drop` payload was worse: the arm made it its own and the enum dropped it too, released twice even when the arm only read it.
// Closed: an enum's payload is lent to the arm; a String handed to a `sink` goes as a copy, and one that cannot be copied is rejected.
// main (before this PR): ASan heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h231 | enum payload String handed to sink in arm; enum drops it again
$ `stdlib/core/string.nu`

: | Msg { Text String Quiet }

@ consume sink String s → v {
}

@ main → i {
    : Msg m @ Msg { Text ( string_from `a string long enough to live on the heap` ) }
    ?? m { Text t → { ( consume t ) } Quiet → {} }
    ^ 0
}
