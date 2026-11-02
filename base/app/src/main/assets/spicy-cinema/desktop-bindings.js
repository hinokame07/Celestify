// Host services imported by the unmodified Spicy Lyrics Fullscreen controller.
// Lyrics are measured and scrolled by the native renderer. Reflow sends its new viewport.
export const PageContainer = document.querySelector("#SpicyLyricsPage"),
  Tooltips = {};
export let IsPIP = false;
export function setPopupMode(enabled) {
  IsPIP = enabled;
}
export const GetPageRoot = () => document.body;
export const isExperimentEnabled = (id) =>
  id === "lyricsSkeleton" &&
  PageContainer.classList.contains("Exp_LyricsSkeleton");
export const Compactify = () => window.stage?.layout(),
  IsCompactMode = () => PageContainer.classList.contains("CompactMode");
export const EnableCompactMode = Compactify,
  OpenNowBar = Compactify;
export const GetCurrentLyricsContainerInstance = () => ({
  Resize: () => window.stage?.measure(),
});
export const SyncNoLyricsLayout = Compactify;
export const $forceCompactMode = { get: () => false },
  $isNowBarOpen = { get: () => true };
export const $currentLyricsData = { get: () => "" };
export const requestCappedFrame = requestAnimationFrame.bind(window),
  cancelCappedFrame = cancelAnimationFrame.bind(window);
// Desktop sidebar, tooltip registry, scroll anchor and NowBar subscription cleanup have no owners
// in this dialog. Android disposes its playback subscriptions when the dialog closes.
const unusedDesktopService = () => {};
export {
  unusedDesktopService as CleanUpNowBarComponents,
  unusedDesktopService as CloseNowBar,
  unusedDesktopService as DeregisterNowBarBtn,
  unusedDesktopService as ResetLastLine,
  unusedDesktopService as SetKawarpSuspended,
};
export default {
  AppendViewControls: Compactify,
  Destroy: () => window.Cinema?.action("close", 0),
};
