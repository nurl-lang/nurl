### Changed

- **A `~ T` loop is left only by its `break`s** (Agora #453; probes
  holder_repointed_*_while_true_*). Since #413 a loop leaves with the
  dependencies its head held, for the run that never enters it. A loop whose
  condition is the literal `T` (or `1`) never ends at its head, yet it was
  joined there too. So a holder repointed right before every `break` was
  refused as still viewing a local that had ended. Such a loop now leaves
  with what its `break`s held. A holder that still views the local on a path
  that breaks is refused as before.
