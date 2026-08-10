// diag_struct_lit_named_fields.nu — a struct literal with Rust-style
// named fields.
//
// NURL struct literals are positional. Every mainstream language a model
// has read names the fields, so this is among the likeliest mistakes it
// can make — and it used to land on "use of undefined identifier 'a'",
// which points at the field name as though it were a typo and never
// mentions that names are not part of the form.
: Point { i x i y }

@ main → i {
    : Point p @ Point { x : 3 y : 4 }
    ^ . p x
}
