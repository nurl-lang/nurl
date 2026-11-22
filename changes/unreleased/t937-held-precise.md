### Changed

- **The formal proof's rule for what a call's result may hold is now more precise** (AGORA-937). The rule used to say the result may hold every root the arguments hold, in every way. It now says the result may hold each of the arguments' own dependencies, combined with each way of reaching inside them. This matches what a result built from the arguments can reach, so the rule is still sound. The proof's model of a call uses the same precise form for what a call places in the caller. Nothing changes in nurlc, and the proof is complete with no theorem weakened.
