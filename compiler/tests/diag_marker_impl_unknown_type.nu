// diag_marker_impl_unknown_type.nu — a '% NotSend' marker whose subject
// type is misspelled.
//
// An impl's SUBJECT is a type position, and it was the last one with no
// declared-type check: `Z NoSuchType`, a cast target and `%Trait` each
// closed the same hole in their own spelling.
//
// The marker traits are what make it matter. `% NotSend Db { }` asserts a
// danger the compiler cannot derive — a `sqlite3*` is an `s`, and `s` is
// Send. A MISSPELLED subject asserted it about a type that does not
// exist: nothing said so, the real `Db` stayed Send, and it crossed the
// thread boundary the marker was written to forbid. A safety assertion
// that silently does nothing is worse than none, because the author reads
// it and stops looking.
//
// check_type_known is not the instrument here — it rejects a bare generic
// TEMPLATE name, and an impl subject is allowed to be one (`% NotSend Rc
// { }` covers every Rc monomorph). So the check accepts what an impl may
// name and rejects only a name that is none of them.
: Db { s handle }

% NotSend Dbb {}

@ ship [T : Send] T v → i { ^ 0 }

@ main → i {
    : Db d @ Db { `x` }
    ^ ( ship [Db] d )
}
