// diag_ax_cures_2.nu — the value-position "forgot the parens" cure.
//
// `^ f 1` is a call with the parentheses left off. The diagnostic used
// to lead with the CLOSURE reading — "does not auto-coerce to a closure
// value. Wrap it: '\ args → R { ( f args ) }'" — which is true, rarer,
// and sends a reader who simply forgot the parens to rewrite working
// code into a closure. The statement-position sibling had said the
// right thing all along ("calls in NURL are written '( name args )'").
//
// Both readings are still offered; the likely one leads.
//
// Expected: COMPILE FAIL naming the parenthesised call form first.

@ f i x → i { ^ x }

@ main → i { ^ f 1 }
