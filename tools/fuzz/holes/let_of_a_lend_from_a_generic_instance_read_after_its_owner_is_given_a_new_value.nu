// let_of_a_lend_from_a_generic_instance_read_after_its_owner_is_given_a_new_value: `: String k ( idg [String] s )  = s ( … )  k`
// Closed: a `:` binding of the result of a call whose callee is compiled after the caller is linked to no owner by codegen (nothing the callee hands back is known at the call), so a store replacing the owner hands it nothing and frees the old value under it; the core IR says so (CORE_VF_UNLINKED), and the reference checker and the engine no longer hand it the old value (agora #1005). nurlc refused it already. A generic instance is compiled after every caller.
// main 198283209: nurlc refuses it; the reference checker and the engine said runs-clean; --no-borrowck: AddressSanitizer: heap-use-after-free (string_data k).
// map: §7.6 | A2 | rejected | - | AGORA-1005: a lend from a generic instance read after its owner is given a new value
$ `stdlib/core/string.nu`

@ idg [T] T x → T { ^ x }

@ main → i {
    : ~ String s ( string_from `a string long enough for the heap buffer here` )
    : String k ( idg [String] s )
    = s ( string_from `another string long enough for the heap buffer` )
    ( nurl_println ( string_data k ) )
    ^ 0
}
