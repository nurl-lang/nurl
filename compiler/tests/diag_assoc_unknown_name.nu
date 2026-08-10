// diag_assoc_unknown_name.nu — an impl binding an associated type the
// trait never declared.
//
// Note the anchor: this check runs after the whole impl is scanned, so
// it reports the line of the NEXT declaration rather than the binding's
// own. It has no captured position to use, unlike the die_pos sites.
// Left as found — the message names the trait, the type and the binding,
// so it identifies itself without the line.
: IntBox { i v }

% Boxed [T] { type Elem @ unwrap T self → Elem }

% Boxed IntBox { type Zzz i @ unwrap IntBox self → i { ^ . self v } }

@ main → i { ^ 0 }
