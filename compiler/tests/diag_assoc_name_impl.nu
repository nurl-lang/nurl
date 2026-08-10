// diag_assoc_name_impl.nu — the same '=' habit on the IMPL side, where
// the binding really does take a concrete type but still takes no '='.
//
// Both this message and its trait-side twin were rewritten to stop
// teaching the '=' form; the coverage gate then flagged both as unread,
// which is the point of keying the ratchet on message identity rather
// than on a count. A rewritten message has been read by nobody.
: IntBox { i v }

% Boxed [T] { type Elem @ unwrap T self → Elem }

% Boxed IntBox {
    type = i
    @ unwrap IntBox self → i { ^ . self v }
}

@ main → i { ^ 0 }
