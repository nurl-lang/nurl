#!/usr/bin/env python3
# brackets — max nesting depth of an embedded bracket string, 0 if unbalanced.
text = "(([{}]))[]{}"
stack = []
depth = 0
maxd = 0
bad = 0
for ch in text:
    c = ord(ch)
    if c in (40, 91, 123):
        stack.append(c)
        depth += 1
        if depth > maxd:
            maxd = depth
    elif c in (41, 93, 125):
        if not stack:
            bad = 1
        else:
            opened = stack.pop()
            want = 40 if c == 41 else c - 2
            if opened != want:
                bad = 1
            depth -= 1
result = maxd if (len(stack) == 0 and bad == 0) else 0
print(result)
