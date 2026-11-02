import { build } from "esbuild";
import { resolve, basename } from "node:path";
const mobileServices = new Set([
  "stores",
  "uiState",
  "experiments",
  "Addons",
  "SpotifyPlayer",
  "PageView",
  "CompactMode",
  "PopupLyrics",
  "ScrollSimplebar",
  "ApplyLyricsCredits",
  "OnApply",
  "fetchLyrics",
]);
await build({
  entryPoints: ["renderer.js"],
  bundle: true,
  format: "esm",
  target: "chrome105",
  minify: true,
  legalComments: "eof",
  outfile: "../../base/app/src/main/assets/spicy-cinema/upstream/renderer.js",
  plugins: [
    {
      name: "android-host",
      setup(b) {
        b.onResolve({ filter: /^\./ }, (a) => {
          const name = basename(a.path).replace(/\.tsx?$/, "");
          if (mobileServices.has(name)) return { path: resolve("services.js") };
          if (name === "Global" || name === "Logger")
            return { path: resolve(name + ".js") };
        });
      },
    },
  ],
});
