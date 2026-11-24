### Changed

- **The core IR says which captures a returned closure's environment owns** (AGORA-978). A closure returned where it is made (`^ \ …`) owns its handle captures: the binding's value is moved in, or copied where the binding borrows. A closure that stays in its frame holds a copy of the handle, which depends on the binding. `nurlc --emit-core` now flags such a capture (variable flag 2048, `CORE_VF_ENVOWN`), so tools/ncore's translation to the formal model can tell the two apart. Nothing else changes: the engine does not ask the flag, and the LLVM output is byte-identical.
