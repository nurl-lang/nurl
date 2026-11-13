### Fixed

- **A `: ~` binding of a join of two owners, given a field of its own, can be given back to one of them** (Agora #819). After `: ~ P q ? == c 1 o r  = . q name ( mk … )`, `= o q` dropped o's old value whole, including the `extra` that q still shared with it on the run q held o's value (a use after free). On that run (q's key, with the fields it replaced put back, is o's) o now keeps its value: what q's field replaced is dropped, and the field is o's. On the run q holds r's value, o is given it as a lend, as before. The same holds for a non-key field and for a call handing q back.
