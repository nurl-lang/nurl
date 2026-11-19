### Fixed

- **A view a callee lends of a user enum's payload ends when the payload is grown through the enum's own match** (AGORA-428, the last shape). `: v ( name_of g )`, then `?? g { GSome q → ( string_push_str . q name … ) }`, left `v` reading freed memory. That is refused now. A match that only reads is still accepted.
