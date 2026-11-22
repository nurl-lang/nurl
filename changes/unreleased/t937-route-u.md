### Changed

- **Formal proof design: calls that change the caller's memory inside a `Vec`'s elements take route U** (AGORA-937). Route F, where a frozen root may change inside, is set aside: a `recover` freezes the caller's whole frame and expects it unchanged after a panic, and the typing cannot tell which frozen roots may change. Route U leaves such a root unfrozen for the call. It relaxes the anchors of a lent `Vec`'s views, and adds premises so that every kill ends no loan. Nothing changes in nurlc.
