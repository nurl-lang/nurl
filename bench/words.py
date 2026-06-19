#!/usr/bin/env python3
# words — count words (maximal runs of ASCII letters) in an embedded string.
def is_letter(o):
    return (97 <= o <= 122) or (65 <= o <= 90)


text = "the quick123brown fox, jumps-over the lazy_dog!"
count = 0
inword = False
for ch in text:
    if is_letter(ord(ch)):
        if not inword:
            count += 1
            inword = True
    else:
        inword = False
print(count)
