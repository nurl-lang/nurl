// diag_enumlit_tag_not_variant.nu — field 0 of an enum literal is the
// variant TAG.
//
// The twin of diag_optlit_tag_not_bool.nu, one type constructor over.
// Every payload slot of an enum literal is checked against the variant's
// declared payload type; the tag slot was checked against nothing, so
// `@ Node { NText ( string_from t ) }` with the variant name deleted
// emitted `insertvalue %Node zeroinitializer, %String %r1, 0` — a String
// in the i64 tag slot, exit 0, IR only clang rejects.
//
// The tag lowers to an integer (a variant NAME is how it is written and
// its tag is what it lowers to), so anything that is not one slid into
// the slot from somewhere else — almost always the payload, because the
// variant name is missing.

: | N { NA i NB s NC }

@ main → i {
    : N n @ N { 1.5 5 }
    ^ 0
}
