// brackets — max nesting depth of an embedded bracket string, 0 if unbalanced.
const text = "(([{}]))[]{}";
const stack = [];
let depth = 0;
let maxd = 0;
let bad = 0;
for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c === 40 || c === 91 || c === 123) {
        stack.push(c);
        depth += 1;
        if (depth > maxd) maxd = depth;
    } else if (c === 41 || c === 93 || c === 125) {
        if (stack.length === 0) {
            bad = 1;
        } else {
            const opened = stack.pop();
            const want = c === 41 ? 40 : c - 2;
            if (opened !== want) bad = 1;
            depth -= 1;
        }
    }
}
const result = stack.length === 0 && bad === 0 ? maxd : 0;
console.log(result);
