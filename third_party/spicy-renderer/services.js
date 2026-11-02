import { atom } from "nanostores";
import SimpleBar from "simplebar";
import { CreditsRow } from "./src/utils/Lyrics/Applyer/Credits/CreditsRow.ts";
export const PageContainer = document.querySelector("#SpicyLyricsPage");
export const IsCompactMode = () =>
  PageContainer.classList.contains("CompactMode");
export let IsPIP = false;
export function setPopupMode(enabled) {
  IsPIP = enabled;
}
export const SpotifyPlayer = {
  get IsPlaying() {
    return !!window.stageClock?.playing;
  },
  GetPosition: () => window.stageClock?.now() ?? 0,
  Seek(ms) {
    window.Cinema?.action("lyricSeek", ms);
  },
};
export const $romanization = atom(false),
  $currentLyricsType = atom("None"),
  $lyricsContainerExists = atom(false),
  $simpleLyricsMode = atom(false),
  $minimalLyricsMode = atom(false),
  $joinSplitWords = atom(false),
  $seekFadeCompensation = atom(true),
  $scrollLeadEnabled = atom(false),
  $scrollLeadMs = atom(250),
  $smoothScrolling = atom(false),
  $animationFpsCapEnabled = atom(false),
  $animationFpsCap = atom(60);
const effects = new Map();
export function $experiment(name) {
  if (!effects.has(name))
    effects.set(name, atom(name === "keepOverlappingLines"));
  return effects.get(name);
}
export const isExperimentEnabled = (id) => $experiment(id).get();
export const ArabicPersianRegex = /[\u0600-\u06FF]/;
export let ScrollSimplebar = null;
export function ClearScrollSimplebar() {
  ScrollSimplebar?.unMount();
  ScrollSimplebar = null;
}
export function MountScrollSimplebar() {
  ScrollSimplebar = new SimpleBar(
    PageContainer.querySelector(".LyricsContent"),
    { autoHide: true },
  );
}
export function RecalculateScrollSimplebar() {
  ScrollSimplebar?.recalculate();
}
export const IsScrollbarDragging = () => !!ScrollSimplebar?.draggedAxis;
export function ClearLyricsPageContainer() {
  PageContainer.querySelector(".LyricsContent").replaceChildren();
}
export function MarkLastLineSide(el, right, rtl) {
  el.classList.toggle("EndsOnOppositeLine", right && !rtl);
}
export function ApplySongCredits(data, container) {
  if (!data.credits?.length) return;
  const group = document.createElement("div");
  group.className = "SongCredits";
  for (const item of data.credits) {
    const row = document.createElement("div");
    if (item.kind === "CONTRIBUTOR") {
      row.className = "SongInfo";
      const name = document.createElement(item.profile ? "a" : "span");
      if (item.profile) name.href = item.profile;
      name.className = "SongInfoName";
      name.textContent = "@" + item.name;
      row.append(item.label + " ", name);
    } else {
      row.className =
        item.kind === "PROVIDER"
          ? "LyricsProvider"
          : item.kind === "NOTE"
            ? "SongInfo"
            : "Credits";
      const text = item.text ?? item;
      const separator = text.indexOf(": ");
      if (separator > 0)
        CreditsRow(row, text.slice(0, separator), text.slice(separator + 2));
      else row.textContent = text;
    }
    group.append(row);
  }
  container.append(group);
}
export const EmitApply = (type) => {
  $currentLyricsType.set(type);
};
export const EmitNotApplyed = () => {
  $currentLyricsType.set("None");
};
