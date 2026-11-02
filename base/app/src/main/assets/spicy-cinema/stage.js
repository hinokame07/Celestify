/* Android binding for Spikerko's PageView, Fullscreen and NowBar (34ad8c6), AGPL-3.0. */
"use strict";
import Fullscreen, { SetControlsDragLock } from "./upstream/Fullscreen.js";
import { Icons } from "./upstream/Icons.js";
import Kawarp from "./upstream/Kawarp.js";
import { setPopupMode } from "./desktop-bindings.js";
import { syncCanvas, swapCanvasSide, suspended } from "./canvas-bindings.js";
import "./upstream/CanvasImmersive.js";
import {
  SkeletonMarkup,
  ShowLyricsSkeleton,
  HideLyricsSkeleton,
} from "./upstream/LyricsSkeleton.js";
const $ = (selector) => document.querySelector(selector);
const page = $("#SpicyLyricsPage"),
  bar = $(".NowBar"),
  media = $(".MediaBox");
const overlay = $(".MediaContent"),
  timeline = $(".Timeline");
const compactQuery = matchMedia("(max-width:70.812rem)");
$(".LyricsContainer").insertAdjacentHTML("afterbegin", SkeletonMarkup);
const send = (name, value = 0) => window.Cinema?.action(name, value);
let song = {},
  forceLayout = null,
  awake = false,
  grabbed = false,
  timer;
let engine,
  documentGeneration = 0,
  lastData = null,
  lastConfig = "";
let at = 0,
  durationMs = 0,
  stamp = 0,
  clockRunning = false,
  clockRate = 1;
window.stageClock = {
  get playing() {
    return clockRunning;
  },
  now() {
    return Math.max(
      0,
      Math.min(
        durationMs,
        at + (clockRunning ? (performance.now() - stamp) * clockRate : 0),
      ),
    );
  },
};
async function setLyrics(data) {
  lastData = data;
  const revision = ++documentGeneration;
  try {
    if (data) engine ??= await import("./upstream/renderer.js");
    if (revision !== documentGeneration) return;
    engine?.wakeRenderer();
    page.classList.toggle("DesktopLyrics", !!data);
    engine?.configure(song.settings || {});
    engine?.render(data, song.romanize);
    measureSoon();
  } catch (err) {
    console.error(err);
    page.classList.remove("DesktopLyrics");
    send("nativeFallback");
  }
}
let visiblePage = true,
  measuring = false,
  geometryUntil = 0,
  lastGeometry = "";
const controls = [
  ["compact", "CompactModeToggle", "EnableCompactModeIcon"],
  ["romanize", "RomanizationToggle", "EnableRomanization"],
  ["side", "NowBarSideToggle", "NowBarSideSwap"],
  ["fullscreen", "FullscreenToggle", "Fullscreen"],
  ["options", "SettingsToggle", "Settings"],
  ["close", "Close", "Close"],
];
$(".ViewControls").innerHTML = controls
  .map(
    ([action, id, icon]) =>
      '<button class="ViewControl" data-action="' +
      action +
      '" id="' +
      id +
      '">' +
      Icons[icon] +
      "</button>",
  )
  .join("");
$(".PlaybackControls").innerHTML =
  '<button class="PlaybackControl ShuffleToggle" data-action="shuffle">' +
  Icons.Shuffle +
  "</button>" +
  Icons.PrevTrack +
  '<button class="PlaybackControl PlayStateToggle" data-action="play">' +
  Icons.Play +
  "</button>" +
  Icons.NextTrack +
  '<button class="PlaybackControl LoopToggle" data-action="repeat">' +
  Icons.Loop +
  "</button>";
$(".PrevTrack").dataset.action = "previous";
$(".NextTrack").dataset.action = "next";
$(".Heart").innerHTML = Icons.Heart;
$(".VolumeIcon").innerHTML = Icons.Volume;
for (const el of document.querySelectorAll("[data-action]")) {
  if (el.tagName !== "BUTTON") {
    el.tabIndex = 0;
    el.setAttribute("role", "button");
    el.onkeydown = (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        el.click();
      }
    };
  }
  el.onclick = () => {
    wake();
    if (el.dataset.action === "compact") {
      forceLayout = !compact();
      layout();
    } else if (el.dataset.action === "close") {
      if (song.reduced) send("close");
      else {
        measureSoon();
        Fullscreen.Close().then((ok) => {
          if (ok) send("close");
        });
      }
    } else send(el.dataset.action);
  };
}
function compact() {
  const landscapePhone =
    innerHeight <= 520 && innerWidth >= 620 && innerWidth > 1.5 * innerHeight;
  return (
    innerWidth < 620 ||
    (forceLayout ?? (compactQuery.matches && !landscapePhone))
  );
}
let requestedSide;
function layout() {
  const small = song.popup || (!song.inline && compact()),
    right = !small && !song.empty && song.lyricsLeft;
  page.classList.toggle("CompactMode", small);
  $("#CompactModeToggle").hidden = innerWidth < 620;
  $(".ContentBox").classList.toggle("LyricsHidden", !!song.empty && !small);
  if (requestedSide !== !!right) {
    requestedSide = !!right;
    const flip = () => {
      for (const [side, on] of [
        ["Right", right],
        ["Left", !right],
      ]) {
        page.classList.toggle("NowBarSide__" + side, !!on);
        bar.classList.toggle(side + "Side", !!on);
      }
      measureSoon();
    };
    if (!swapCanvasSide(flip, right ? "right" : "left")) flip();
  }
  $("#CompactModeToggle").innerHTML =
    Icons[small ? "DisableCompactModeIcon" : "EnableCompactModeIcon"];
  bar.classList.toggle("LockedMediaBox", small && !!song.locked);
  page.classList.toggle("TouchOpen", small && awake && !song.locked);
  const outside =
    (!small && song.timeline !== false) ||
    page.classList.contains("CanvasImmersive");
  const parent = outside ? $(".Header") : overlay;
  if (timeline.parentElement !== parent)
    parent.insertBefore(timeline, outside ? $(".Metadata") : null);
  measureSoon();
  playback();
}
function measureSoon() {
  geometryUntil = performance.now() + 520;
  if (measuring) return;
  measuring = true;
  function measure() {
    const a = $("#nativeLyrics").getBoundingClientRect(),
      b = media.getBoundingClientRect();
    const top = Math.max(0, $(".LyricsContainer").getBoundingClientRect().top);
    const values = [
      a.left / innerWidth,
      top / innerHeight,
      a.width / innerWidth,
      (innerHeight - top) / innerHeight,
      b.left / innerWidth,
      b.top / innerHeight,
      b.width / innerWidth,
      b.height / innerHeight,
    ].map((n) => Number(n.toFixed(5)));
    const json = JSON.stringify(values);
    if (json !== lastGeometry) {
      lastGeometry = json;
      window.Cinema?.layout(json);
    }
    if (performance.now() < geometryUntil) requestAnimationFrame(measure);
    else measuring = false;
  }
  requestAnimationFrame(measure);
}
function show(on, focus = false) {
  awake = on;
  overlay.toggleAttribute("data-visible", on);
  // Translate touch into the events consumed by the original fullscreen springs.
  if (on) media.dispatchEvent(new MouseEvent("mouseenter"));
  else {
    media.dispatchEvent(new MouseEvent("mouseleave"));
    page.dispatchEvent(new MouseEvent("mouseleave"));
  }
  page.classList.toggle("TouchOpen", compact() && on && !song.locked);
  measureSoon();
}
function wake(ms = 3500) {
  clearTimeout(timer);
  show(true, true);
  timer = setTimeout(() => {
    if (!grabbed) show(false);
  }, ms);
}
for (const event of ["pointerdown", "wheel", "touchmove"])
  document.addEventListener(event, () => engine?.wakeRenderer(), {
    passive: true,
  });
media.addEventListener(
  "pointerdown",
  (e) => {
    if (!awake) {
      wake();
      e.stopPropagation();
    }
  },
  true,
);
$(".MediaImageContainer").onclick = () => wake();
$(".MediaImageContainer").onkeydown = (e) => {
  if (e.key === "Enter") wake();
};
document.addEventListener("pointermove", (e) => {
  if (e.pointerType === "mouse" && !grabbed)
    wake(media.contains(e.target) ? 3500 : 750);
});
document.addEventListener("focusin", (e) => {
  if (e.target.matches(":focus-visible")) wake(10000);
});
function setIcon(el, svg) {
  if (el._icon !== svg) {
    el.innerHTML = svg;
    el._icon = svg;
  }
}
function fmt(ms) {
  const sec = Math.floor(Math.max(0, ms) / 1000);
  return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0");
}
function tick(
  position,
  duration,
  volume,
  lyricPosition = position,
  running = song.playing,
  rate = 1,
) {
  const previous = window.stageClock.now(),
    drift = lyricPosition - previous;
  if (clockRunning !== running || Math.abs(drift) > 80) engine?.wakeRenderer();
  at =
    Math.abs(drift) > 120 || clockRunning !== running || !running
      ? lyricPosition
      : previous + drift * 0.35;
  durationMs = duration;
  stamp = performance.now();
  clockRunning = !!running;
  clockRate = rate;
  song.duration = duration;
  if (!grabbed) {
    $(".Time.Position").textContent = fmt(position);
    $(".Time.Duration").textContent = fmt(duration);
    $(".SliderBar").style.setProperty(
      "--SliderProgress",
      duration > 0 ? position / duration : 0,
    );
    $(".VolumeControl").style.setProperty("--VolumeLevel", volume);
    for (const [s, p] of [
      [".SliderBar", duration > 0 ? position / duration : 0],
      [".VolumeControl", volume],
    ])
      $(s).setAttribute("aria-valuenow", Math.round(p * 100));
  }
}
function slider(selector, action) {
  const el = $(selector);
  function move(e, done) {
    const r = el.getBoundingClientRect(),
      vertical = action === "volume" && r.height > r.width;
    const x = Math.max(
      0,
      Math.min(
        1,
        vertical
          ? 1 - (e.clientY - r.top) / r.height
          : (e.clientX - r.left) / r.width,
      ),
    );
    el.style.setProperty(
      action === "volume" ? "--VolumeLevel" : "--SliderProgress",
      x,
    );
    if (action === "seek") {
      const time = fmt(x * (song.duration || 0));
      $(".Time.Position").textContent = time;
      if (song.preview && !done) {
        const bubble = $(".ScrubPreview");
        bubble.hidden = false;
        bubble.textContent = time;
        bubble.style.left = x * 100 + "%";
      }
    }
    if (done || action === "volume") send(action, x);
  }
  el.onpointerdown = (e) => {
    grabbed = true;
    wake();
    SetControlsDragLock(true);
    el.classList.add("Dragging");
    el.setPointerCapture(e.pointerId);
    move(e, false);
  };
  el.onpointermove = (e) => {
    if (el.hasPointerCapture(e.pointerId)) move(e, false);
  };
  el.onpointerup = (e) => {
    if (el.hasPointerCapture(e.pointerId)) move(e, true);
  };
  el.onlostpointercapture = () => {
    grabbed = false;
    SetControlsDragLock(false);
    $(".ScrubPreview").hidden = true;
    el.classList.remove("Dragging");
    wake();
  };
  el.onkeydown = (e) => {
    if (["ArrowRight", "ArrowLeft", "ArrowUp", "ArrowDown"].includes(e.key)) {
      e.preventDefault();
      send(
        action,
        Math.max(
          0,
          Math.min(
            1,
            Number(el.getAttribute("aria-valuenow")) / 100 +
              (["ArrowRight", "ArrowUp"].includes(e.key) ? 0.05 : -0.05),
          ),
        ),
      );
    }
  };
}
const bubble = document.createElement("span");
bubble.className = "ScrubPreview";
bubble.hidden = true;
timeline.append(bubble);
slider(".SliderBar", "seek");
slider(".VolumeControl", "volume");
function playback() {
  syncCanvas(song, visiblePage, page.classList.contains("CompactMode"));
  updateWarp();
}
let hasCanvasClass = false;
new MutationObserver(() => {
  const active = page.classList.contains("CanvasImmersive");
  if (active !== hasCanvasClass) {
    hasCanvasClass = active;
    layout();
  }
}).observe(page, { attributes: true, attributeFilter: ["class"] });
function setSong(s) {
  song = s;
  setPopupMode(!!s.popup);
  document.body.classList.toggle("spicy-pip-wrapper", !!s.popup);
  page.classList.toggle("Exp_PopupDock", !!s.popup && !!s.popupDock);
  page.classList.toggle("Exp_RefinedCredits", s.refinedCredits !== false);
  const full = !s.inline || !!s.popup;
  if (full && !Fullscreen.IsOpen) Fullscreen.Open(true, false);
  if (!full && Fullscreen.IsOpen) Fullscreen.CloseImmediately();
  $(".SongName span").textContent = s.title;
  $(".Artists span").textContent = s.artist;
  setIcon($(".PlayStateToggle"), s.playing ? Icons.Pause : Icons.Play);
  setIcon($(".LoopToggle"), s.repeat === 2 ? Icons.LoopTrack : Icons.Loop);
  setIcon(
    $("#FullscreenToggle"),
    s.fullscreen ? Icons.CloseFullscreen : Icons.Fullscreen,
  );
  setIcon(
    $("#RomanizationToggle"),
    s.romanize ? Icons.DisableRomanization : Icons.EnableRomanization,
  );
  $(".ShuffleToggle").classList.toggle("Enabled", s.shuffle);
  $(".LoopToggle").classList.toggle("Enabled", s.repeat !== 0);
  $(".Heart").classList.toggle("Filled", s.liked);
  page.classList.toggle("Clip", s.video);
  page.classList.toggle("Reduced", s.reduced);
  page.classList.toggle("Exp_NewProgressBar", s.glassSlider !== false);
  page.classList.toggle("Exp_RefinedBackground", s.refined !== false);
  page.classList.toggle("NoLineHoverBackground", s.hover === false);
  page.classList.toggle("SystemFont", !!s.systemFont);
  page.classList.toggle("Exp_LyricsSkeleton", !!s.skeleton);
  if (s.loading && s.skeleton) ShowLyricsSkeleton();
  else HideLyricsSkeleton();
  page.classList.toggle("Inline", !full);
  page.classList.toggle("Fullscreen", full);
  page.classList.toggle("ShowVolumeSlider", s.volumeSlider !== false);
  page.classList.toggle("NoGlow", s.glow === false);
  for (const [css, key] of [
    ["SimpleLyricsMode", "simpleLyricsMode"],
    ["MinimalLyricsMode", "minimalLyricsMode"],
    ["DuetLinePadding", "duets"],
    ["CreditsFollowLastLine", "credits"],
    ["Exp_RefreshedSimpleLyrics", "refreshedSimpleLyrics"],
    ["Exp_KeepOverlappingLines", "keepOverlappingLines"],
    ["Exp_BackgroundLinePop", "backgroundLinePop"],
  ])
    page.classList.toggle(css, !!s.settings?.[key]);
  const options = JSON.stringify([s.settings, s.romanize]);
  if (lastData && options !== lastConfig) setLyrics(lastData);
  lastConfig = options;
  page.style.setProperty("--userScale", s.scale || 1);
  for (const el of document.querySelectorAll("[data-action]"))
    el.setAttribute("aria-label", s.labels[el.dataset.action]);
  $(".VolumeControl").setAttribute("aria-label", s.labels.volume);
  $(".SliderBar").setAttribute("aria-label", s.labels.seek);
  $(".MediaImageContainer").setAttribute("aria-label", s.labels.controls);
  layout();
  background();
}
let warp = null,
  warpSpeed = 0.1,
  poster = "",
  loadedPoster = "",
  warpTimer = 0,
  generation = 0,
  warpFailed = false;
async function updateWarp() {
  const canvas = $("#warp");
  const active =
    visiblePage &&
    song.bg === "dynamic" &&
    poster &&
    !song.video &&
    !suspended &&
    !warpFailed;
  cancelAnimationFrame(warpTimer);
  canvas.hidden = !active;
  if (!active) return;
  try {
    const speed = song.playing ? 1 : 0.1;
    if (!warp) {
      warpSpeed = speed;
      warp = new Kawarp(canvas, {
        warpIntensity: 1,
        blurPasses: 8,
        animationSpeed: speed,
        saturation: 1.5,
        dithering: 0.008,
        transitionDuration: 500,
        tintIntensity: 0,
        scale: 1,
      });
      warp.start();
      cancelAnimationFrame(warp.animationId);
      warp.animationId = null;
    } else if (speed !== warpSpeed) {
      warp.setOptions({ animationSpeed: speed });
      warpSpeed = speed;
    }
    if (loadedPoster !== poster) {
      const rev = ++generation;
      loadedPoster = poster;
      await warp.loadImage(poster);
      if (rev !== generation) return;
    }
    if (!canvas.hidden) {
      warp.renderFrame();
      if (song.motion) {
        const fps = song.settings?.animationFpsCapEnabled
          ? song.settings.animationFpsCap
          : 0;
        const last = performance.now();
        function next(now) {
          if (!fps || now - last >= 1000 / fps - 1) updateWarp();
          else warpTimer = requestAnimationFrame(next);
        }
        cancelAnimationFrame(warpTimer);
        warpTimer = requestAnimationFrame(next);
      }
    }
  } catch {
    warpFailed = true;
    canvas.hidden = true;
    warp?.dispose();
    warp = null;
  }
}
let artistPoster = "";
function background() {
  const style = song.bg,
    image = $(".StaticArtwork"),
    colors = $(".ColorBackground");
  image.hidden = !["cover", "artist"].includes(style) || song.video;
  if (!image.hidden) {
    const url = style === "artist" && artistPoster ? artistPoster : poster;
    let layer = image.lastElementChild;
    if (!layer || layer.imageUrl !== url) {
      const previous = layer;
      layer = document.createElement("div");
      layer.imageUrl = url;
      layer.className = "spicy-dynamic-bg StaticBackground transition_In";
      layer.style.setProperty("--BackgroundImage", 'url("' + url + '")');
      image.appendChild(layer);
      if (previous)
        setTimeout(() => previous.remove(), song.reduced ? 0 : 1400);
    }
    image.style.setProperty("--BackgroundImageBlur", (song.blur || 0) + "px");
  }
  colors.hidden = style !== "color" || song.video;
  if (!colors.hidden)
    for (const [key, factor] of [
      ["MinContrastColor", 0.6],
      ["HighContrastColor", 0.35],
      ["DeepColor", 0.3],
      ["WashColor", 0.55],
    ]) {
      colors.style.setProperty(
        "--" + key,
        mean.map((c) => Math.round(c * factor)).join(",") + ",1",
      );
    }
}
let mean = [40, 40, 40];
async function average(url) {
  if (!url) return;
  const img = new Image();
  img.src = url;
  try {
    await img.decode();
    if (poster !== url) return;
    const c = document.createElement("canvas");
    c.width = c.height = 8;
    const ctx = c.getContext("2d");
    ctx.drawImage(img, 0, 0, 8, 8);
    const pixels = ctx.getImageData(0, 0, 8, 8).data,
      sum = [0, 0, 0];
    for (let i = 0; i < pixels.length; i += 4)
      for (let j = 0; j < 3; j++) sum[j] += pixels[i + j];
    mean = sum.map((channel) => channel / 64);
    background();
  } catch {
    /* Preserve the last palette if the incoming cover cannot decode. */
  }
}
window.stage = {
  setSong,
  setLyrics,
  tick,
  wake,
  layout,
  measure: measureSoon,
  artist(url) {
    artistPoster = url;
    background();
  },
  cover(url) {
    // Keep the preceding WebGL texture during an asynchronous Glide decode. A real
    // transition then blends two covers instead of flashing the underlying window.
    if (!url && song.hasArtwork && poster) return;
    poster = url;
    $(".MediaImageContainer").style.backgroundImage = url
      ? 'url("' + url + '")'
      : "none";
    average(url);
    updateWarp();
    background();
  },
  visible(on) {
    visiblePage = on;
    window.stageVisible = on;
    if (on) engine?.wakeRenderer();
    playback();
  },
};
window.addEventListener("resize", layout);
window.addEventListener("canvas:warp", updateWarp);
measureSoon();
window.addEventListener("pagehide", () => {
  visiblePage = false;
  cancelAnimationFrame(warpTimer);
  window.dispatchEvent(new Event("page:destroy"));
  warp?.dispose();
  Fullscreen.CloseImmediately();
});
