import { PageContainer } from "../desktop-bindings.js";
import { isExperimentEnabled } from "../desktop-bindings.js";
const DEFAULT_LABEL = "Loading Lyrics";
const LINE_WIDTHS = [
    74,
    58,
    86,
    49,
    68,
    81,
    55,
    72,
    63,
    84,
    52,
    77,
    66,
    88,
    57,
    70
];
export const SkeletonMarkup = `
  <div class="LyricsSkeleton">
    <div class="SkeletonLines" aria-hidden="true">
      ${LINE_WIDTHS.map((w, i)=>`<div class="SkeletonLine" style="width: ${w}%; --i: ${i}"></div>`).join("")}
    </div>
    <div class="SkeletonStatus" role="status" aria-live="polite">
      <span class="SkeletonLabel">${DEFAULT_LABEL}</span><span class="SkeletonDots" aria-hidden="true"><i></i><i></i><i></i></span>
    </div>
  </div>`;
export const IsLyricsSkeletonEnabled = ()=>isExperimentEnabled("lyricsSkeleton");
const getSkeleton = ()=>PageContainer?.querySelector(".LyricsContainer .LyricsSkeleton") ?? null;
export function ShowLyricsSkeleton(label = DEFAULT_LABEL) {
    const skeleton = getSkeleton();
    if (!skeleton) return;
    const labelEl = skeleton.querySelector(".SkeletonLabel");
    if (labelEl && labelEl.textContent !== label) labelEl.textContent = label;
    skeleton.classList.toggle("LongLabel", label !== DEFAULT_LABEL);
    skeleton.classList.add("active");
}
export function HideLyricsSkeleton() {
    getSkeleton()?.classList.remove("active");
}
export function PaintLyricsSkeleton() {
    ShowLyricsSkeleton();
    if (document.hidden) return Promise.resolve();
    return new Promise((resolve)=>{
        const fallback = setTimeout(resolve, 100);
        requestAnimationFrame(()=>requestAnimationFrame(()=>{
                clearTimeout(fallback);
                resolve();
            }));
    });
}
