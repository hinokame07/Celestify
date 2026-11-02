// Run: node tools/test-cinema.mjs <path to playwright-core/index.mjs> <Chromium executable>
import assert from "node:assert/strict";
import { readFile, mkdir } from "node:fs/promises";
import { pathToFileURL } from "node:url";
const { chromium } = await import(pathToFileURL(process.argv[2]));
const browser = await chromium.launch({
  executablePath: process.argv[3],
  headless: true,
});
const base = new URL(
  "../base/app/src/main/assets/spicy-cinema/",
  import.meta.url,
);
try {
  const p = await browser.newPage({
    viewport: { width: 1280, height: 800 },
    hasTouch: true,
  });
  const errors = [];
  p.on("pageerror", (err) => errors.push(err.message));
  p.on("console", (m) => {
    if (m.type() === "error") errors.push(m.text());
  });
  await p.route("https://stage.test/**", async (route) => {
    const path =
      new URL(route.request().url()).pathname.slice(1) || "index.html";
    const font = path === "res/font/inter.ttf";
    const type = font
      ? "font/ttf"
      : path.endsWith(".js")
        ? "text/javascript"
        : path.endsWith(".css")
          ? "text/css"
          : "text/html";
    await route.fulfill({
      body: await readFile(
        new URL(font ? "../../res/font/inter.ttf" : path, base),
      ),
      contentType: type,
    });
  });
  await p.addInitScript(() => {
    window.events = [];
    window.Cinema = {
      layout(json) {
        window.rects = JSON.parse(json);
      },
      action(n, v) {
        events.push([n, v]);
      },
    };
  });
  await p.goto("https://stage.test/");
  await p
    .waitForFunction(() => window.stage && window.rects, null, {
      timeout: 5000,
    })
    .catch(() => {
      throw Error(errors.join("\n") || "Stage never became ready");
    });
  const song = {
    title: "Above the clouds",
    artist: "Celestify",
    playing: false,
    reduced: false,
    inline: false,
    lyricsLeft: false,
    video: false,
    canvas: "",
    repeat: 0,
    liked: false,
    labels: {},
    empty: false,
  };
  await p.evaluate((s) => window.stage.setSong(s), song);
  const poster = await p.evaluate(() => {
    const c = document.createElement("canvas");
    c.width = c.height = 256;
    const ctx = c.getContext("2d");
    const g = ctx.createLinearGradient(0, 0, 256, 256);
    g.addColorStop(0, "#e8a674");
    g.addColorStop(0.48, "#30365c");
    g.addColorStop(1, "#96bab4");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 256, 256);
    ctx.fillStyle = "#a4c1b8";
    ctx.beginPath();
    ctx.arc(167, 75, 34, 0, Math.PI * 2);
    ctx.fill();
    return c.toDataURL();
  });
  await p.evaluate((img) => window.stage.cover(img), poster);
  // Sample the actual WebGL output directly after a draw (before the backbuffer is cleared).
  await p.evaluate(async () => {
    const { default: Kawarp } = await import("./upstream/Kawarp.js");
    const draw = Kawarp.prototype.renderFrame;
    const sample = document.createElement("canvas");
    sample.width = sample.height = 8;
    const ctx = sample.getContext("2d", { willReadFrequently: true });
    window.warpFrames = new Set();
    Kawarp.prototype.renderFrame = function (...args) {
      const result = draw.apply(this, args);
      ctx.drawImage(document.querySelector("#warp"), 0, 0, 8, 8);
      const pixels = ctx.getImageData(0, 0, 8, 8).data;
      if (pixels.some((v, i) => i % 4 !== 3 && v > 5))
        window.warpFrames.add(pixels.join(","));
      return result;
    };
  });
  for (const bg of ["artist", "cover", "color", "none", "dynamic"]) {
    await p.evaluate((s) => window.stage.setSong(s), {
      ...song,
      bg,
      playing: bg === "dynamic",
      blur: 8,
      motion: true,
    });
    if (bg === "cover" || bg === "artist")
      assert.ok(await p.locator(".StaticArtwork").isVisible());
    if (bg === "color")
      assert.ok(await p.locator(".ColorBackground").isVisible());
    if (bg === "none")
      assert.equal(await p.locator("#warp").isVisible(), false);
  }
  await p.waitForFunction(() => warpFrames.size > 1, null, { timeout: 10000 });
  // Local 96x96 test pattern. The intercepted CDN request never leaves Chromium.
  const mediaBytes = await readFile(
    new URL("./fixtures/spicy-canvas.webm", import.meta.url),
  );
  const canvasUrl = "https://canvaz.scdn.co/test.webm";
  assert.ok(mediaBytes.length > 100, "recorded video fixture");
  let mediaRequests = 0;
  await p.route(canvasUrl, (route) => {
    mediaRequests++;
    const range = route.request().headers().range;
    const start = Number(/bytes=(\d+)/.exec(range)?.[1] || 0);
    const bytes = Buffer.from(mediaBytes).subarray(start);
    return route.fulfill({
      status: range ? 206 : 200,
      body: bytes,
      headers: {
        "Content-Type": "video/webm",
        "Content-Length": String(bytes.length),
        "Accept-Ranges": "bytes",
        "Cross-Origin-Resource-Policy": "cross-origin",
        "Access-Control-Allow-Origin": "*",
        ...(range
          ? {
              "Content-Range":
                "bytes " +
                start +
                "-" +
                (mediaBytes.length - 1) +
                "/" +
                mediaBytes.length,
            }
          : {}),
      },
    });
  });
  await p.evaluate(
    ({ s, url }) =>
      window.stage.setSong({ ...s, canvas: url, playing: true, bg: "dynamic" }),
    { s: song, url: canvasUrl },
  );
  await p
    .waitForSelector(".CanvasImmersive .CanvasLayer.Current video", {
      state: "attached",
      timeout: 12000,
    })
    .catch(async (e) => {
      const state = await p.evaluate(() => ({
        page: document.querySelector("main").className,
        media: [...document.querySelectorAll("video")].map((v) => [
          v.currentSrc,
          v.readyState,
          v.error?.message,
        ]),
      }));
      throw new Error(
        e +
          " " +
          JSON.stringify(state) +
          " requests=" +
          mediaRequests +
          " bytes=" +
          mediaBytes.length +
          " " +
          errors.join(","),
      );
    });
  assert.equal(await p.locator(".CanvasLayer video").count(), 2);
  await p.waitForFunction(
    () => document.querySelector(".CanvasLayer.Current video")?.currentTime > 0,
  );
  await p.evaluate(
    ({ s, url }) =>
      window.stage.setSong({
        ...s,
        canvas: url,
        playing: true,
        bg: "dynamic",
        lyricsLeft: true,
      }),
    { s: song, url: canvasUrl },
  );
  await p.waitForSelector(".CanvasImmersive.NowBarSide__Right");
  await p.evaluate(
    ({ s, url }) =>
      window.stage.setSong({
        ...s,
        canvas: url,
        playing: false,
        bg: "dynamic",
      }),
    { s: song, url: canvasUrl },
  );
  await p.waitForFunction(
    () => document.querySelector(".CanvasLayer.Current video")?.paused,
  );
  await p.evaluate((s) => window.stage.setSong({ ...s, bg: "dynamic" }), song);
  const rects = () => p.evaluate(() => window.rects);
  await p.waitForFunction(()=>
    !document.querySelector(".CanvasImmersive") &&
    document.querySelector(".NowBarSide__Left") && rects[0] >= rects[4]+rects[6] && rects[5]>.07,
    null,{timeout:4000});
  let [x, y, w, h, mx, my, mw, mh] = await rects();
  const close = (a, b) =>
    assert.ok(Math.abs(a - b) < 0.015, `expected ${a} ≈ ${b}`);
  // CSS min(30cqw,52cqh)*1.1. Square cover, separated from the native lyric hit area.
  close(mw, 0.33);
  close(mw * 1280, mh * 800);
  assert.ok(x >= mx + mw && w > 0.4 && my > 0.07);
  await p.evaluate(() => window.stage.wake());
  await p.locator(".NextTrack").click();
  assert.equal(await p.evaluate(() => events.at(-1)[0]), "next");
  await p.locator("#NowBarSideToggle").click();
  assert.equal(await p.evaluate(() => events.at(-1)[0]), "side");
  await p.evaluate((s) => window.stage.setSong(s), {
    ...song,
    lyricsLeft: true,
  });
  await p.waitForFunction(
    () => rects[4] > 0.5 && rects[0] + rects[2] <= rects[4],
  );
  await p.evaluate(() => window.stage.tick(72000, 200000, 0.4));
  assert.equal(await p.locator(".Time.Position").innerText(), "1:12");
  await p.locator(".SliderBar").click();
  assert.equal(await p.evaluate(() => events.at(-1)[0]), "seek");
  const data = {
    Type: "Syllable",
    credits: [{ kind: "PROVIDER", text: "Provided by: Local TTML" }],
    StartTime: 0,
    Content: [0, 4, 8].map((t, i) => ({
      OppositeAligned: i === 1,
      Lead: {
        StartTime: t,
        EndTime: t + 3,
        Syllables: [
          { Text: "Long", StartTime: t, EndTime: t + 2.2 },
          { Text: "night", StartTime: t + 2.2, EndTime: t + 3 },
        ],
      },
      Background:
        i === 1
          ? [
              {
                StartTime: 4,
                EndTime: 5,
                Syllables: [{ Text: "oh", StartTime: 4, EndTime: 5 }],
              },
            ]
          : [],
    })),
  };
  await p.evaluate((d) => window.stage.setLyrics(d), data);
  await p.evaluate(() => window.stage.tick(4500, 12000, 0.5, 4500, false));
  await p
    .waitForFunction(
      () => document.querySelector(".line.Active")?.textContent?.length,
      null,
      { timeout: 4000 },
    )
    .catch(async (e) => {
      throw Error(
        e +
          " " +
          errors.join("\n") +
          " " +
          (await p.locator(".LyricsContent").first().innerText()),
      );
    });
  assert.ok((await p.locator(".line.OppositeAligned").count()) > 0);
  assert.equal(
    await p.locator(".SongCredits .LyricsProvider .CreditsValue").innerText(),
    "Local TTML",
  );
  assert.ok((await p.locator(".letterGroup .Emphasis").count()) > 0);
  await p.evaluate(() => window.stage.tick(500, 12000, 0.5, 500, false));
  await p.waitForFunction(
    () =>
      !document
        .querySelector(".line.Active")
        ?.classList.contains("OppositeAligned"),
  );
  await p.evaluate(() =>
    window.stage.setLyrics({
      Type: "Line",
      StartTime: 0,
      Content: [
        { Text: "First verse", StartTime: 0, EndTime: 4 },
        { Text: "Last verse", StartTime: 8, EndTime: 10 },
      ],
    }),
  );
  await p.evaluate(() => window.stage.tick(9000, 12000, 0.5, 9000, false));
  await p.waitForFunction(
    () => document.querySelector(".line.Active")?.textContent === "Last verse",
    null,
    { timeout: 3000 },
  );
  if (process.env.CINEMA_QA_DIR) {
    await mkdir(process.env.CINEMA_QA_DIR, { recursive: true });
    const sample = {
      Type: "Line",
      StartTime: 0,
      Content: [
        "Across the open sky",
        "Above the clouds",
        "We follow the light",
        "Until the morning comes",
        "Over the quiet sea",
        "I hear you sing",
      ].map((Text, i) => ({ Text, StartTime: i * 4, EndTime: i * 4 + 3.8 })),
    };
    await p.evaluate((s) => window.stage.setSong(s), {
      ...song,
      bg: "dynamic",
      motion: true,
    });
    await p.evaluate((d) => window.stage.setLyrics(d), sample);
    await p.evaluate(() => window.stage.tick(4800, 24000, 0.45, 4800, false));
    await p.waitForFunction(
      () =>
        document.querySelector(".line.Active")?.textContent ===
        "Above the clouds",
    );
    await p.mouse.move(1260, 790);
    await p.waitForTimeout(1500);
    await p.screenshot({
      path: process.env.CINEMA_QA_DIR + "/cinema-tablet.png",
    });
    const up = process.env.SPICY_UPSTREAM;
    if (up) {
      // Reference PageView template + original CSS and original lyric engine. Freeze playback
      // on the same line; this is an isolated upstream comparison, not Spotify Desktop.
      const ts = await readFile(
        up + "/src/components/Pages/PageView.ts",
        "utf8",
      );
      const template = ts
        .match(/elem\.innerHTML = `([\s\S]*?)`;/)[1]
        .replace(/\$\{SkeletonMarkup\}/g, "");
      const reference = await browser.newPage({
        viewport: { width: 1280, height: 800 },
      });
      const referenceHTML =
        '<meta charset="utf-8"><style>*{box-sizing:border-box}body{font:700 16px system-ui;color:white;background:#252936;--spice-sidebar:#111}</style>' +
        [
          "tokens.css",
          "default.css",
          "ContentBox.css",
          "Simplebar.css",
          "Lyrics/main.css",
          "Lyrics/Mixed.css",
        ]
          .map((f) => '<link rel="stylesheet" href="/css/' + f + '">')
          .join("") +
        '<main id="SpicyLyricsPage" class="Fullscreen SpicyRenderer NowBarSide__Left NowBarStatus__Open Exp_NewProgressBar">' +
        template +
        "</main>";
      await reference.route("https://stage.test/**", async (route) => {
        const path = new URL(route.request().url()).pathname;
        const body = path.startsWith("/css/")
          ? await readFile(up + "/src" + path)
          : path === "/engine.js"
            ? await readFile(new URL("upstream/renderer.js", base))
            : referenceHTML;
        await route.fulfill({
          body,
          contentType:
            path === "/engine.js"
              ? "text/javascript"
              : path.startsWith("/css/")
                ? "text/css"
                : "text/html",
        });
      });
      await reference.goto("https://stage.test");
      await reference.evaluate(
        async ({ poster, sample }) => {
          const $ = (s) => document.querySelector(s);
          $(".NowBar").classList.add("LeftSide", "Active");
          $(".MediaImageContainer").style.backgroundImage =
            "url(" + poster + ")";
          $(".SongName span").textContent = "Above the clouds";
          $(".Artists span").textContent = "Celestify";
          const tl = document.createElement("div");
          tl.className = "Timeline";
          tl.textContent = "0:04　　　　　　　　　0:24";
          $(".Metadata").before(tl);
          window.stageClock = { playing: false, now: () => 4800 };
          const engine = await import("/engine.js");
          engine.render(sample, false);
        },
        { poster, sample },
      );
      await reference.waitForFunction(
        () =>
          document.querySelector(".line.Active")?.textContent ===
          "Above the clouds",
      );
      await reference.waitForTimeout(650);
      const ref = await reference.locator(".MediaBox").boundingBox(),
        actual = await p.locator(".MediaBox").boundingBox();
      assert.ok(
        ["x", "y", "width", "height"].every(
          (key) => Math.abs(ref[key] - actual[key]) < 2,
        ),
        "cover geometry: " + JSON.stringify({ ref, actual }),
      );
      await reference.screenshot({
        path: process.env.CINEMA_QA_DIR + "/spicy-reference.png",
      });
      await reference.close();
    }
  }
  await p.evaluate(() => window.stage.setLyrics(null));
  await p.evaluate((s) => window.stage.setSong(s), {
    ...song,
    lyricsLeft: true,
  });
  await p.setViewportSize({ width: 800, height: 1100 });
  await p.waitForFunction(
    () => document.querySelector(".CompactMode") && rects[1] > 0.15,
  );
  const long = {
    Type: "Line",
    StartTime: 0,
    Content: Array.from({ length: 260 }, (_, i) => ({
      Text: "Verse " + i,
      StartTime: i * 2,
      EndTime: i * 2 + 1.9,
    })),
  };
  await p.evaluate((d) => window.stage.setLyrics(d), long);
  await p.evaluate(() =>
    window.stage.tick(439000, 520000, 0.45, 439000, false),
  );
  await p.waitForFunction(
    () => document.querySelector(".line.Active")?.textContent === "Verse 219",
    null,
    { timeout: 5000 },
  );
  assert.ok(
    (await p.locator(".line").count()) < 180,
    "virtualizer should not mount all 260 rows",
  );
  for (let i = 0; i < 12; i++) {
    await p.evaluate(
      ({ i, song }) => {
        window.stage.setSong({ ...song, title: "Track " + i });
        window.stage.tick(2000 * i, 520000, 0.45, 2000 * i, i % 2 === 0);
      },
      { i, song },
    );
  }
  await p.evaluate(() => window.stage.visible(false));
  await p.evaluate(() => window.stage.visible(true));
  await p.evaluate(
    (s) => window.stage.setSong({ ...s, lyricsLeft: true }),
    song,
  );
  await p.evaluate(() => window.stage.wake());
  await p.locator("#CompactModeToggle").click();
  await p
    .waitForFunction(
      () => !document.querySelector(".CompactMode") && rects[4] > 0.5,
      null,
      { timeout: 2500 },
    )
    .catch(async (err) => {
      throw Error(
        err +
          " " +
          (await p.evaluate(() =>
            JSON.stringify([
              document.querySelector("main").className,
              rects,
              events,
            ]),
          )),
      );
    });
  await p.setViewportSize({ width: 390, height: 844 });
  await p.evaluate(
    (s) => window.stage.setSong({ ...s, bg: "dynamic", playing: false }),
    song,
  );
  await p.evaluate(() => window.stage.tick(14000, 520000, 0.5, 14000, false));
  if (process.env.CINEMA_QA_DIR) {
    await p.waitForTimeout(800);
    await p.screenshot({
      path: process.env.CINEMA_QA_DIR + "/cinema-phone.png",
    });
  }
  await p.waitForFunction(
    () => document.querySelector(".CompactMode") && rects[1] > 0.15,
  );
  await p.setViewportSize({ width: 844, height: 390 });
  await p.waitForFunction(
    () =>
      !document.querySelector(".CompactMode") &&
      rects[0] >= rects[4] + rects[6] - 0.01,
  );
  await p.setViewportSize({ width: 390, height: 844 });
  await p.waitForSelector(".CompactMode");
  await p.evaluate(() => window.stage.wake());
  await p.locator("#Close").click();
  await p.waitForFunction(() => events.some(([n]) => n === "close"));
  await p.evaluate((s) => window.stage.setSong({ ...s, inline: true }), song);
  await p.waitForSelector("main.Inline");
  await p.evaluate((s) => window.stage.setSong(s), song);
  await p.evaluate(() => window.stage.wake());
  await p.locator("#Close").click();
  await p.waitForFunction(
    () => events.filter(([n]) => n === "close").length === 2,
  );
  await p.setViewportSize({ width: 320, height: 200 });
  await p.evaluate(
    (s) =>
      window.stage.setSong({
        ...s,
        inline: true,
        popup: true,
        popupDock: true,
      }),
    song,
  );
  await p.waitForSelector(
    "body.spicy-pip-wrapper main.Exp_PopupDock.Fullscreen.CompactMode",
  );
  await p
    .waitForFunction(
      () =>
        document.querySelector(".LyricsContainer").getBoundingClientRect()
          .bottom < 195,
      null,
      { timeout: 1500 },
    )
    .catch(() => {});
  const dockLyrics = await p.locator(".LyricsContainer").boundingBox();
  assert.ok(
    dockLyrics.height > 40 && dockLyrics.y + dockLyrics.height < 195,
    "popup reserves the player dock: " + JSON.stringify(dockLyrics),
  );
  assert.deepEqual(errors, []);
  console.log(
    "Verified original wide/compact stage, side swap, transport, seek, tablet override and animated close.",
  );
} finally {
  await browser.close();
}
