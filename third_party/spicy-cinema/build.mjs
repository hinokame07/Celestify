// Rebuild with Node 24+. The upstream TypeScript bodies remain unchanged. Only imports whose
// owner is Spotify Desktop are linked to Android services. No package install or network access.
import { stripTypeScriptTypes } from "node:module";
import { readFileSync, writeFileSync } from "node:fs";
const dst = new URL(
  "../../base/app/src/main/assets/spicy-cinema/upstream/",
  import.meta.url,
);
for (const name of [
  "Fullscreen",
  "Icons",
  "TransferElement",
  "Spring",
  "Maid",
  "Scheduler",
  "LyricsSkeleton",
  "CanvasImmersive",
]) {
  let src = readFileSync(new URL(name + ".ts", import.meta.url), "utf8");
  src = stripTypeScriptTypes(src, { mode: "transform" });
  src = src.replace(/^import "[^"]+\.css";$/gm, "");
  src = src.replace(/from "([^"]+)"/g, (statement, path) => {
    const leaf = path.split("/").at(-1).replace(/\.ts$/, "");
    if (["Scheduler", "Maid", "Spring", "TransferElement"].includes(leaf))
      return 'from "./' + leaf + '.js"';
    if (leaf === "Global") return 'from "../events.js"';
    if (name === "CanvasImmersive") return 'from "../canvas-bindings.js"';
    return 'from "../desktop-bindings.js"';
  });
  writeFileSync(new URL(name + ".js", dst), src);
}
