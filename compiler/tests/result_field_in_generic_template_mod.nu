// fixture: module; helper for result_field_in_generic_template.nu: a public
// generic struct whose field is a result type `! A B`, named `Impl` - the
// name of a struct private_handle_payload_mod.nu keeps private. A field name
// is not a type: the template check must not judge it as one.
$ `compiler/tests/private_handle_payload_mod.nu`

pub : RB [A B] { ! A B Impl i n }
