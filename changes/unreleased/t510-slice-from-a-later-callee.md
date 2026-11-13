### Fixed

- **A slice from a function compiled after its caller is released** (Agora #510). The caller read the callee's ownership before the callee had a summary, so a slice from a function defined below it, or from a generic instance (`( mk [i] 1 2 )`), was taken for a lend and never freed. The caller now reads the callee's answer at run time: per call where the callee answers per call, else its static answer, resolved at module end (`@.__nurl_retslc.N`). A parameter's field handed back stays lent.
