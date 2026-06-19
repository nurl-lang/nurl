// brackets — max nesting depth of an embedded bracket string, 0 if unbalanced.
fn main() {
    let text = "(([{}]))[]{}";
    let mut stack: Vec<u8> = Vec::new();
    let mut depth = 0i64;
    let mut maxd = 0i64;
    let mut bad = 0;
    for &c in text.as_bytes() {
        if c == 40 || c == 91 || c == 123 {
            stack.push(c);
            depth += 1;
            if depth > maxd {
                maxd = depth;
            }
        } else if c == 41 || c == 93 || c == 125 {
            if stack.is_empty() {
                bad = 1;
            } else {
                let opened = stack.pop().unwrap();
                let want = if c == 41 { 40 } else { c - 2 };
                if opened != want {
                    bad = 1;
                }
                depth -= 1;
            }
        }
    }
    let result = if stack.is_empty() && bad == 0 { maxd } else { 0 };
    println!("{}", result);
}
