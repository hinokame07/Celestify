
import { $backgroundStyle } from "../canvas-bindings.js";
import { isExperimentEnabled, onExperimentChange } from "../canvas-bindings.js";
import { onAnimationFrame } from "../canvas-bindings.js";
import Logger from "../canvas-bindings.js";
import { getRemoteConfig } from "../canvas-bindings.js";
import Global from "../events.js";
import { SpotifyPlayer } from "../canvas-bindings.js";
import { IsCardMode, PageContainer } from "../canvas-bindings.js";
import { IsPIP } from "../canvas-bindings.js";
import { IsCompactMode } from "../canvas-bindings.js";
import { SetSideSwapTransition } from "../canvas-bindings.js";
import { getBackgroundStyle, PAGE_BACKGROUND_KEY, SetKawarpSuspended } from "../canvas-bindings.js";
import { AttachCanvasMedia, GetPlayingCanvasInfo, LoadCanvasMedia } from "../canvas-bindings.js";
const immersiveLogger = new Logger("Canvas Immersive");
const ACTIVE_CLASS = "CanvasImmersive";
const FADE_MS = 900;
const AMBIENT_WIDTH = 80;
const AMBIENT_INTERVAL_MS = 1000 / 30;
const AMBIENT_FILTER = "blur(5px) saturate(2.5) brightness(0.65)";
const DOCK_GLIDE_MS = 600;
const DOCK_ROWS = ".Header > .Metadata .SongName, .Header > .Metadata .Artists, .Header .Timeline";
const SWAP_OUT_MS = 160;
const SWAP_IN_MS = 420;
const SWAP_DRIFT = 0.025;
const THEME_BACKGROUND_CLASSES = [
    "st-bgimg-active",
    "st-animbg-solid",
    "st-mv-active"
];
const themeOwnsBackground = (page)=>THEME_BACKGROUND_CLASSES.some((cls)=>page.classList.contains(cls));
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let mount = null;
let active = false;
let generation = 0;
let suspendTimer = null;
let retryTimer = null;
let retryFileId = null;
let retryAttempt = 0;
let sideSwap = null;
let lastAmbientDraw = 0;
let lastAmbientTime = -1;
let ambientPrimed = false;
function createVideo() {
    const video = document.createElement("video");
    video.muted = true;
    video.loop = true;
    video.playsInline = true;
    video.preload = "auto";
    video.disablePictureInPicture = true;
    video.setAttribute("aria-hidden", "true");
    return video;
}
function createLayer() {
    const box = document.createElement("div");
    box.className = "CanvasLayer";
    const video = createVideo();
    box.append(video);
    return {
        box,
        video,
        detach: null,
        fileId: null,
        releaseTimer: null
    };
}
function applyAmbientFilter(ctx) {
    ctx.filter = AMBIENT_FILTER;
}
function MountOnPage(page) {
    if (mount?.page === page) return;
    Unmount();
    const contentBox = page.querySelector(".ContentBox");
    const nowBar = contentBox?.querySelector(".NowBar");
    const header = nowBar?.querySelector(".CenteredView .Header");
    if (!contentBox || !nowBar || !header) return;
    const ambient = document.createElement("canvas");
    ambient.className = "CanvasAmbient";
    ambient.width = AMBIENT_WIDTH;
    ambient.height = Math.round(AMBIENT_WIDTH * 9 / 16);
    const ambientCtx = ambient.getContext("2d", {
        alpha: false
    });
    if (!ambientCtx) return;
    applyAmbientFilter(ambientCtx);
    contentBox.prepend(ambient);
    const stage = document.createElement("div");
    stage.className = "CanvasStage";
    const layers = [
        createLayer(),
        createLayer()
    ];
    const frame = document.createElement("div");
    frame.className = "CanvasStageFrame";
    frame.append(layers[0].box, layers[1].box);
    stage.append(frame);
    nowBar.before(stage);
    const resizeObserver = new ResizeObserver(()=>{
        if (!mount) return;
        resizeAmbient(mount, contentBox);
        if (active) updateSquareTop(mount);
    });
    resizeObserver.observe(contentBox);
    resizeObserver.observe(nowBar);
    let themeOwned = themeOwnsBackground(page);
    const themeObserver = new MutationObserver(()=>{
        const owned = themeOwnsBackground(page);
        if (owned === themeOwned) return;
        themeOwned = owned;
        void Refresh();
    });
    themeObserver.observe(page, {
        attributes: true,
        attributeFilter: [
            "class"
        ]
    });
    mount = {
        page,
        nowBar,
        header,
        stage,
        ambient,
        ambientCtx,
        layers,
        current: 0,
        resizeObserver,
        themeObserver
    };
}
function Unmount() {
    if (!mount) return;
    finishSideSwap();
    generation++;
    active = false;
    clearSuspendTimer();
    clearRetryTimer();
    SetKawarpSuspended(PAGE_BACKGROUND_KEY, false);
    mount.resizeObserver.disconnect();
    mount.themeObserver.disconnect();
    for (const layer of mount.layers)releaseLayer(layer);
    mount.page.classList.remove(ACTIVE_CLASS);
    mount.ambient.remove();
    mount.stage.remove();
    mount.nowBar.style.removeProperty("--CanvasSquareTop");
    mount = null;
}
function releaseLayer(layer) {
    if (layer.releaseTimer) clearTimeout(layer.releaseTimer);
    layer.releaseTimer = null;
    layer.video.pause();
    layer.box.classList.remove("Current", "Leaving");
    if (layer.detach) {
        layer.detach();
        const fresh = createVideo();
        layer.video.replaceWith(fresh);
        layer.video = fresh;
    }
    layer.detach = null;
    layer.fileId = null;
}
function clearSuspendTimer() {
    if (suspendTimer) clearTimeout(suspendTimer);
    suspendTimer = null;
}
function clearRetryTimer() {
    if (retryTimer) clearTimeout(retryTimer);
    retryTimer = null;
}
function scheduleRetry(fileId) {
    if (retryFileId !== fileId) {
        retryFileId = fileId;
        retryAttempt = 0;
    }
    const delay = getRemoteConfig().canvas.retryDelaysMs[retryAttempt];
    if (delay === undefined) return;
    retryAttempt++;
    const gen = generation;
    clearRetryTimer();
    retryTimer = setTimeout(()=>{
        retryTimer = null;
        if (gen === generation) void Refresh(true);
    }, delay);
}
function resizeAmbient(m, contentBox) {
    const { clientWidth: w, clientHeight: h } = contentBox;
    if (!w || !h) return;
    const height = Math.max(1, Math.round(AMBIENT_WIDTH * h / w));
    if (m.ambient.height !== height) {
        m.ambient.height = height;
        applyAmbientFilter(m.ambientCtx);
        ambientPrimed = false;
        lastAmbientTime = -1;
    }
}
function updateSquareTop(m) {
    const mediaBox = m.header.querySelector(":scope > .MediaBox");
    if (!mediaBox) return;
    const top = mediaBox.getBoundingClientRect().top - m.nowBar.getBoundingClientRect().top;
    m.nowBar.style.setProperty("--CanvasSquareTop", `${Math.round(top)}px`);
}
function toggleDockLayout(m, on) {
    const rows = [
        ...m.nowBar.querySelectorAll(DOCK_ROWS)
    ];
    const before = rows.map((row)=>row.getBoundingClientRect());
    m.page.classList.toggle(ACTIVE_CLASS, on);
    if (on) updateSquareTop(m);
    if (reducedMotion.matches) return;
    rows.forEach((row, i)=>{
        const after = row.getBoundingClientRect();
        const dx = before[i].left - after.left;
        const dy = before[i].top - after.top;
        if (!before[i].width || Math.abs(dx) < 1 && Math.abs(dy) < 1) return;
        row.animate([
            {
                translate: `${dx}px ${dy}px`
            },
            {
                translate: "0 0"
            }
        ], {
            duration: DOCK_GLIDE_MS,
            easing: "cubic-bezier(0.77, 0, 0.175, 1)"
        });
    });
}
function swapLayers(m, nowBar) {
    return [
        {
            el: m.stage,
            fade: false,
            drift: true
        },
        {
            el: m.stage.firstElementChild,
            fade: true,
            drift: false
        },
        {
            el: nowBar,
            fade: true,
            drift: true
        }
    ];
}
function playSwapLeg(layers, from, to, options) {
    const starts = layers.map(({ el })=>{
        if (from) return {
            opacity: String(from.opacity),
            translate: `${from.x}px 0`
        };
        const style = getComputedStyle(el);
        return {
            opacity: style.opacity,
            translate: style.translate === "none" ? "0 0" : style.translate
        };
    });
    for (const animation of sideSwap?.animations ?? [])animation.cancel();
    return layers.map(({ el, fade, drift }, i)=>{
        const start = {};
        const end = {};
        if (fade) {
            start.opacity = starts[i].opacity;
            end.opacity = to.opacity;
        }
        if (drift) {
            start.translate = starts[i].translate;
            end.translate = `${to.x}px 0`;
        }
        return el.animate([
            start,
            end
        ], options);
    });
}
function finishSideSwap() {
    const swap = sideSwap;
    if (!swap) return;
    sideSwap = null;
    for (const animation of swap.animations)animation.cancel();
    swap.apply?.();
    swap.nowBar.style.removeProperty("transition");
}
function transitionSideSwap(applySwap, to) {
    const m = mount;
    if (!m || !active || reducedMotion.matches || !m.page.classList.contains("NowBarStatus__Open")) {
        finishSideSwap();
        return false;
    }
    const nowBar = m.page.querySelector(".ContentBox > .NowBar");
    if (!nowBar) return false;
    const layers = swapLayers(m, nowBar);
    if (sideSwap?.apply) {
        const swap = sideSwap;
        swap.apply = null;
        swap.animations = playSwapLeg(layers, null, {
            opacity: 1,
            x: 0
        }, {
            duration: SWAP_IN_MS,
            easing: "cubic-bezier(0.23, 1, 0.32, 1)"
        });
        swap.animations[0].finished.then(()=>sideSwap === swap && finishSideSwap(), ()=>undefined);
        return true;
    }
    const direction = to === "left" ? -1 : 1;
    const drift = m.page.clientWidth * SWAP_DRIFT * direction;
    const swap = {
        animations: sideSwap?.animations ?? [],
        apply: applySwap,
        nowBar
    };
    sideSwap = swap;
    swap.animations = playSwapLeg(layers, null, {
        opacity: 0,
        x: drift
    }, {
        duration: SWAP_OUT_MS,
        easing: "cubic-bezier(0.4, 0, 1, 1)",
        fill: "forwards"
    });
    swap.animations[0].finished.then(()=>{
        if (sideSwap !== swap || !swap.apply) return;
        nowBar.style.transition = "none";
        swap.apply();
        swap.apply = null;
        swap.animations = playSwapLeg(layers, {
            opacity: 0,
            x: -drift
        }, {
            opacity: 1,
            x: 0
        }, {
            duration: SWAP_IN_MS,
            easing: "cubic-bezier(0.23, 1, 0.32, 1)"
        });
        swap.animations[0].finished.then(()=>sideSwap === swap && finishSideSwap(), ()=>undefined);
    }, ()=>undefined);
    return true;
}
function isEligible() {
    return isExperimentEnabled("canvasImmersive") && !!PageContainer && PageContainer.classList.contains("NowBarStatus__Open") && !IsCardMode && !IsPIP && !IsCompactMode() && getBackgroundStyle() === "dynamic" && !themeOwnsBackground(PageContainer);
}
function syncPlayback() {
    if (!mount) return;
    const shouldPlay = active && SpotifyPlayer.IsPlaying && !mount.page.ownerDocument.hidden;
    for (const [index, layer] of mount.layers.entries()){
        if (!layer.fileId) continue;
        if (shouldPlay && index === mount.current) {
            layer.video.play().catch(()=>undefined);
        } else {
            layer.video.pause();
        }
    }
    lastAmbientTime = -1;
}
function activate() {
    if (!mount || active) return;
    active = true;
    ambientPrimed = false;
    toggleDockLayout(mount, true);
    clearSuspendTimer();
    suspendTimer = setTimeout(()=>{
        suspendTimer = null;
        if (active) SetKawarpSuspended(PAGE_BACKGROUND_KEY, true);
    }, FADE_MS);
}
function deactivate() {
    if (!mount || !active) return;
    finishSideSwap();
    active = false;
    clearSuspendTimer();
    SetKawarpSuspended(PAGE_BACKGROUND_KEY, false);
    toggleDockLayout(mount, false);
    const gen = generation;
    const m = mount;
    setTimeout(()=>{
        if (gen !== generation || active || mount !== m) return;
        for (const layer of m.layers)releaseLayer(layer);
    }, FADE_MS);
}
function waitForFrame(video) {
    if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA && !video.seeking) return Promise.resolve();
    return new Promise((resolve)=>{
        const done = ()=>{
            video.removeEventListener("loadeddata", check);
            video.removeEventListener("seeked", check);
            resolve();
        };
        const check = ()=>{
            if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA && !video.seeking) done();
        };
        video.addEventListener("loadeddata", check);
        video.addEventListener("seeked", check);
        setTimeout(done, 3000);
    });
}
async function Refresh(isRetry = false) {
    const gen = ++generation;
    clearRetryTimer();
    if (!isRetry) retryAttempt = 0;
    if (!isExperimentEnabled("canvasImmersive")) {
        if (!mount) return;
        deactivate();
        const m = mount;
        setTimeout(()=>{
            if (gen === generation && mount === m && !active) Unmount();
        }, FADE_MS);
        return;
    }
    if (PageContainer && PageContainer !== mount?.page && !IsCardMode && !IsPIP) MountOnPage(PageContainer);
    if (!mount) return;
    const info = isEligible() ? GetPlayingCanvasInfo() : null;
    if (!info) {
        deactivate();
        return;
    }
    const m = mount;
    const currentLayer = m.layers[m.current];
    if (currentLayer.fileId === info.fileId) {
        activate();
        syncPlayback();
        return;
    }
    const media = await LoadCanvasMedia(info);
    if (gen !== generation || mount !== m) return;
    if (!media) {
        deactivate();
        scheduleRetry(info.fileId);
        return;
    }
    retryFileId = null;
    const nextIndex = m.current === 0 ? 1 : 0;
    const next = m.layers[nextIndex];
    releaseLayer(next);
    let detach;
    try {
        detach = await AttachCanvasMedia(next.video, media);
    } catch (err) {
        immersiveLogger.warn("Canvas playback failed", media.fileId, err);
        if (gen === generation) deactivate();
        return;
    }
    if (gen !== generation || mount !== m) {
        detach();
        return;
    }
    next.detach = detach;
    next.fileId = media.fileId;
    if (media.type === "VIDEO_LOOPING_RANDOM" && media.durationMs > 0) {
        next.video.currentTime = Math.random() * (media.durationMs / 1000);
    }
    await waitForFrame(next.video);
    if (gen !== generation || mount !== m) return;
    const previous = m.layers[m.current];
    m.current = nextIndex;
    next.box.classList.add("Current");
    previous.box.classList.replace("Current", "Leaving");
    activate();
    syncPlayback();
    if (previous.releaseTimer) clearTimeout(previous.releaseTimer);
    previous.releaseTimer = setTimeout(()=>{
        previous.releaseTimer = null;
        if (mount === m && m.layers[m.current] !== previous) releaseLayer(previous);
    }, FADE_MS);
}
onAnimationFrame((timestamp)=>{
    if (!mount || !active) return;
    if (timestamp - lastAmbientDraw < AMBIENT_INTERVAL_MS) return;
    const video = mount.layers[mount.current].video;
    if (video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA || video.currentTime === lastAmbientTime) return;
    lastAmbientDraw = timestamp;
    lastAmbientTime = video.currentTime;
    const { ambient, ambientCtx: ctx } = mount;
    const w = ambient.width;
    const h = ambient.height;
    const scale = Math.max(w / video.videoWidth, h / video.videoHeight) * 1.3;
    const dw = video.videoWidth * scale;
    const dh = video.videoHeight * scale;
    ctx.globalAlpha = ambientPrimed ? 0.3 : 1;
    ctx.drawImage(video, (w - dw) / 2, (h - dh) / 2, dw, dh);
    ambientPrimed = true;
});
Global.Event.listen("page:open", ()=>void Refresh());
Global.Event.listen("page:destroy", Unmount);
Global.Event.listen("playback:songchange", ()=>void Refresh());
Global.Event.listen("playback:playpause", syncPlayback);
const onFullscreenChange = ()=>setTimeout(()=>{
        syncPlayback();
        if (mount && active) updateSquareTop(mount);
    }, 0);
Global.Event.listen("fullscreen:open", onFullscreenChange);
Global.Event.listen("fullscreen:exit", onFullscreenChange);
Global.Event.listen("compact-mode:enable", ()=>void Refresh());
Global.Event.listen("compact-mode:disable", ()=>void Refresh());
Global.Event.listen("nowbar:open", ()=>void Refresh());
Global.Event.listen("nowbar:close", ()=>void Refresh());
onExperimentChange((experiment)=>{
    if (experiment.id === "canvasImmersive") void Refresh();
});
$backgroundStyle.listen(()=>void Refresh());
SetSideSwapTransition(transitionSideSwap);
document.addEventListener("visibilitychange", syncPlayback);
