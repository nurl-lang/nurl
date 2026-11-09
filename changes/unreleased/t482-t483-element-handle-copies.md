### Fixed

- **A `~` loop's element ends with the element of its container it is** (Agora #482). A change could drop or replace the container's elements through another name: a `vec_clear` through an alias or a cursor, a function or a closure that clears them, a new value for what a borrowed container is in. The loop's element stayed readable after that, and the loop went on to its next element, both reading freed memory (a heap-use-after-free). Reading the element after such a change is now an error, and so is going on to the next round; leave the loop with `break` right after the change. A `??` payload read on the element, and a `~ cond` loop whose condition reads a borrow the body ended, are checked the same way.
- **A closure over a lent value is tied to the container's element** (Agora #483). A closure could capture by value a `vec_at` or `vec_get` binding, a field borrow, a `??` payload or a parameter's element; so could one a call returns over such a value. It depended on nothing. Kept past the container, run after the container's elements were cleared, or sent to a thread after that, it read freed memory. It now ends when the container ends or its elements are dropped or replaced. The container growing, or the element growing, leaves it be.

### Changed

- A closure over a `~` loop's element, or one a call returned over a lent value, is no longer refused when run after that element's own buffer grew (Agora #483).
- Refused as their `vec_at` or name spellings are: a `vec_set` of another row while a loop's element is read; a clear or a pop through an alias, or through a value a call lends of the container, followed by the loop's next round; a closure over a lent element run after another element was popped.
