### Fixed

- **A cursor given a value of its own, then handed to a `sink`, takes only that value** (Agora #668). `: ~ ( Vec String ) w u  = w ( vec_new … )  ( eat w )` cleared u's drop flag through w's alias link, so u's Vec was dropped by no one (leak); the same for a String and a struct. A `sink` now asks, by the value's identity, whether the cursor still holds its source's value, as a store or a return moving it on already did. With that, a `: ~` binding of a value block's tail (`: ~ String e { : String s … s }`, then a sink) is routed like the plain `:` one: it was freed twice.
