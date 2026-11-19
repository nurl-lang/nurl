### Fixed

- **A literal that takes a binding in can no longer be handed to a callee beside a view of that binding** (AGORA-926). `( use2 @ S { b 0 } sv )`, with b moved into the literal and sv, a view of b, as a separate argument, was accepted, while `( use3 b sv )` was refused. So was `( vec_push vs @ S { sv b } )`, a literal of an owner and a view of it handed to a keeping callee. A callee that grew b left the view reading freed memory. Both are refused now: keep the view and its owner in different values, or take the view again from the field when you need it.
