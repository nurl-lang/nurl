// A struct literal that leaves a Vec field out would make it zero bytes,
// which is not a Vec: outside `unsafe` the field is given (h180).
$ `stdlib/core/vec.nu`

: Bag { i n ( Vec i ) items }

@ main → i {
    : Bag b @ Bag { 5 }
    ^ ( vec_len [i] . b items )
}
