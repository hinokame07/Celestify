// Media URL and playback state come from Celestify. CanvasImmersive owns both video layers,
// the original ambient compositor, crossfades and side-swap choreography.
export { IsPIP, IsCompactMode, PageContainer } from "./desktop-bindings.js";
export const IsCardMode = false,
  PAGE_BACKGROUND_KEY = "page";
export const getRemoteConfig = () => ({
  canvas: { retryDelaysMs: [3000, 10000, 30000] },
});
export default class Logger {
  warn(...args) {
    console.warn(...args);
  }
}
let model = {},
  visible = true,
  modeKey = "",
  style,
  frame,
  request,
  transition;
export let suspended = false;
export function SetKawarpSuspended(key, value) {
  if (key !== PAGE_BACKGROUND_KEY || suspended === value) return;
  suspended = value;
  window.dispatchEvent(new Event("canvas:warp"));
}
export function SetSideSwapTransition(fn) {
  transition = fn;
}
export function swapCanvasSide(apply, side) {
  return transition?.(apply, side);
}
export const SpotifyPlayer = {
  get IsPlaying() {
    return !!model.playing && visible;
  },
};
export const getBackgroundStyle = () => model.bg;
export const isExperimentEnabled = (id) =>
  id === "canvasImmersive" && !!model.canvas && !model.video && !model.inline;
export const onExperimentChange = (fn) =>
  window.addEventListener("canvas:config", () => fn({ id: "canvasImmersive" }));
export const $backgroundStyle = {
  listen: (fn) => window.addEventListener("canvas:style", fn),
};
export const GetPlayingCanvasInfo = () =>
  model.canvas ? { fileId: model.canvas } : null;
export async function LoadCanvasMedia(info) {
  const url = new URL(info.fileId);
  if (
    url.protocol !== "https:" ||
    !/\.(scdn\.co|spotifycdn\.com)$/.test(url.hostname)
  )
    return null;
  return info;
}
const pending = new WeakMap();
export async function AttachCanvasMedia(video, media) {
  pending.get(video)?.abort();
  const controller = new AbortController(),
    signal = controller.signal;
  pending.set(video, controller);
  let timeout;
  try {
    await new Promise((resolve, reject) => {
      video.addEventListener("loadeddata", resolve, { once: true, signal });
      video.addEventListener(
        "error",
        () => reject(new Error("Canvas unavailable")),
        { once: true, signal },
      );
      signal.addEventListener(
        "abort",
        () => reject(new Error("Canvas replaced")),
        { once: true },
      );
      timeout = setTimeout(
        () => reject(new Error("Canvas load timed out")),
        10000,
      );
      video.src = media.fileId;
      video.load();
    });
  } finally {
    clearTimeout(timeout);
    controller.abort();
    if (pending.get(video) === controller) pending.delete(video);
  }
  return () => {
    if (video.getAttribute("src") !== media.fileId) return;
    video.pause();
    video.removeAttribute("src");
    video.load();
  };
}
function schedule() {
  if (!request && frame && visible && model.canvas)
    request = requestAnimationFrame((time) => {
      request = 0;
      frame(time);
      if (SpotifyPlayer.IsPlaying && document.querySelector(".CanvasImmersive"))
        schedule();
    });
}
export function onAnimationFrame(fn) {
  frame = fn;
  schedule();
}
export function syncCanvas(next, shown, compact) {
  const playing = SpotifyPlayer.IsPlaying;
  model = next;
  visible = shown;
  const key = JSON.stringify([
    next.track,
    next.canvas,
    next.inline,
    next.popup,
    next.video,
    compact,
  ]);
  if (key !== modeKey) {
    modeKey = key;
    window.dispatchEvent(new Event("canvas:config"));
  } else if (style !== next.bg) window.dispatchEvent(new Event("canvas:style"));
  style = next.bg;
  if (SpotifyPlayer.IsPlaying !== playing)
    window.dispatchEvent(new Event("playback:playpause"));
  if (!shown) {
    cancelAnimationFrame(request);
    request = 0;
  } else schedule();
}
