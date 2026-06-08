const fs = require("fs");
const path = require("path");

const pkgPath = path.resolve(__dirname, "..", "package.json");
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));

const parts = pkg.version.split(".").map(Number);
parts[2] += 1;
pkg.version = parts.join(".");

fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");

console.log(`Bumped zig-snowflake to v${pkg.version}`);
