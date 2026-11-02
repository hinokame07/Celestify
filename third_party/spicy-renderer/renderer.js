// Real desktop applyers + animator + virtualizer. Android supplies the document and clock.
import { ApplySyllableLyrics } from "./src/utils/Lyrics/Applyer/Synced/Syllable.ts";
import { ApplyLineLyrics } from "./src/utils/Lyrics/Applyer/Synced/Line.ts";
import {
  InitializeScrollEvents,
  CleanupScrollEvents,
  ScrollToActiveLine,
  ResetLastLine,
  QueueForceScroll,
} from "./src/utils/Scrolling/ScrollToActiveLine.ts";
import {
  addLinesEvListener,
  removeLinesEvListener,
  LyricsObject,
} from "./src/utils/Lyrics/lyrics.ts";
import { DestroyAllLyricsContainers } from "./src/utils/Lyrics/Applyer/CreateLyricsContainer.ts";
import { onAnimationFrame } from "./src/utils/AnimationFrameLoop.ts";
export { wakeRenderer } from "./src/utils/AnimationFrameLoop.ts";
import * as s from "./services.js";
export function configure(options) {
  s.setPopupMode(!!options.popup);
  for (const name of [
    "simpleLyricsMode",
    "minimalLyricsMode",
    "smoothScrolling",
    "joinSplitWords",
    "scrollLeadEnabled",
    "scrollLeadMs",
    "seekFadeCompensation",
    "animationFpsCapEnabled",
    "animationFpsCap",
  ]) {
    if (options[name] !== undefined) s["$" + name].set(options[name]);
  }
  for (const name of [
    "backgroundLinePop",
    "refreshedSimpleLyrics",
    "keepOverlappingLines",
  ])
    if (options[name] !== undefined) s.$experiment(name).set(options[name]);
}
export function render(data, romanize) {
  CleanupScrollEvents();
  removeLinesEvListener();
  ResetLastLine();
  DestroyAllLyricsContainers();
  s.ClearScrollSimplebar();
  s.ClearLyricsPageContainer();
  s.$lyricsContainerExists.set(!!data);
  s.$currentLyricsType.set(data?.Type || "None");
  if (!data) return;
  if (data.Type === "Syllable") ApplySyllableLyrics(data, romanize);
  else ApplyLineLyrics(data, romanize);
  const display = LyricsObject.Types[data.Type].Lines.filter(
    (line) => !line.DotLine,
  );
  const notes = data.Content.flatMap((line) => [
    line.translation,
    ...(line.Background || []).map((v) => v.translation),
  ]);
  display.forEach((line, i) => {
    if (!notes[i]) return;
    const translation = document.createElement("small");
    translation.className = "UnderLineTranslation";
    translation.textContent = notes[i];
    line.HTMLElement.append(translation);
  });
  addLinesEvListener();
  InitializeScrollEvents(s.ScrollSimplebar);
  QueueForceScroll();
}
export function follow() {
  ResetLastLine();
  QueueForceScroll();
}
onAnimationFrame(() => {
  if (s.$lyricsContainerExists.get() && s.ScrollSimplebar)
    ScrollToActiveLine(s.ScrollSimplebar);
});
