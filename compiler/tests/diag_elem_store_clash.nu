// diag_elem_store_clash.nu — storing a float into an integer slice
// element. Six sites in the compiler emit this same sentence for
// different container shapes; this covers the slice-element one.
@ main → i {
    : [i xs [i | 1 2 3]
    = . xs 0 1.5
    ^ 0
}
