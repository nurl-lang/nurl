// fixture: module; helper for diag_private_type_in_generic_template.nu: a
// module whose public generic struct names, in a field, a type that another
// strict module (private_handle_payload_mod.nu) keeps private.
$ `compiler/tests/private_handle_payload_mod.nu`
$ `stdlib/core/vec.nu`

pub : GW [T] { ( Vec Impl ) v T x }
