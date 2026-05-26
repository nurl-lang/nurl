// json_parse — parse bench/data.json 50 times via V8 JSON.parse.
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "data.json"), "utf8");
let ok = 0;
for (let i = 0; i < 5; i++) {
    const obj = JSON.parse(src);
    if (obj !== null) ok++;
}
console.log(ok);
