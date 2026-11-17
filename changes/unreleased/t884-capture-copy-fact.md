### Changed

- **The ownership engine reads a closure's copy-in to a captured owner from the compiler's own record of it** (AGORA-884). Code is generated per AGORA-872: a value a call lends of a closure's local is copied into a captured owner on the runs the call lent. The core IR now marks the stored value (`CORE_VF_CPCOPY`), and the engine and the reference checker in tools/ncore read that mark. Before, they re-derived the copy, which could disagree with the generated code. No program's verdict changes.
