// words — count words (maximal runs of ASCII letters) in an embedded string.
function isLetter(c) {
    return (c >= 97 && c <= 122) || (c >= 65 && c <= 90);
}

const text = "the quick123brown fox, jumps-over the lazy_dog!";
let count = 0;
let inword = false;
for (let i = 0; i < text.length; i++) {
    if (isLetter(text.charCodeAt(i))) {
        if (!inword) {
            count += 1;
            inword = true;
        }
    } else {
        inword = false;
    }
}
console.log(count);
