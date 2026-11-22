### Changed

- **The formal proof's rule for a call through a package now tracks its result more precisely** (AGORA-937). The rule used to say that the result depends on every root the package reaches, in every way. It now says the result depends on each of the package's own dependencies, combined with each way of reaching inside them. That matches what the package's environment can reach, so the rule is still sound. It also lets the next step model a call's regions exactly. Nothing changes in nurlc, and the proof is complete with no theorem weakened.
