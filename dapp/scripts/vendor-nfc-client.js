#!/usr/bin/env node
/** Build @chimpdao/nfc-client from the vendored bridge git dependency. */
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const bridge = join(root, "node_modules/chimpdao-nfc-bridge");

if (!existsSync(bridge)) {
  console.log("vendor-nfc-client: no chimpdao-nfc-bridge in node_modules, skipping");
  process.exit(0);
}

const clientDist = join(bridge, "packages/client/dist/index.js");
if (existsSync(clientDist)) {
  console.log("vendor-nfc-client: client already built");
  process.exit(0);
}

console.log("vendor-nfc-client: building bridge packages…");
execSync("npm install && npm run build:packages", {
  cwd: bridge,
  stdio: "inherit",
});
