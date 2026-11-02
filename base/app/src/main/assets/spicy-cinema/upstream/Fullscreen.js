import { GetCurrentLyricsContainerInstance } from "../desktop-bindings.js";
import { SyncNoLyricsLayout } from "../desktop-bindings.js";
import { ResetLastLine } from "../desktop-bindings.js";
import { $currentLyricsData } from "../desktop-bindings.js";
import { $forceCompactMode, $isNowBarOpen } from "../desktop-bindings.js";
import Global from "../events.js";
import { SetKawarpSuspended } from "../desktop-bindings.js";
import PageView, { Compactify, GetPageRoot, PageContainer, Tooltips } from "../desktop-bindings.js";
import { EnableCompactMode, IsCompactMode } from "../desktop-bindings.js";
import { CleanUpNowBarComponents, CloseNowBar, DeregisterNowBarBtn, OpenNowBar } from "../desktop-bindings.js";
import TransferElement from "./TransferElement.js";
import { IsPIP } from "../desktop-bindings.js";
import { Spring } from "./Spring.js";
import { Maid } from "./Maid.js";
import Scheduler from "./Scheduler.js";
import { cancelCappedFrame, requestCappedFrame } from "../desktop-bindings.js";
const Fullscreen = {
    Open,
    Close,
    CloseImmediately,
    Toggle,
    IsOpen: false,
    CinemaViewOpen: false
};
const ControlsMaid = new Maid();
const controlsOpacitySpring = new Spring(0, 2, 2, 0);
const artworkBrightnessSpring = new Spring(0, 2, 2, 0);
const dockLiftSpring = new Spring(0, 2.5, 1, 0);
let animationLastTimestamp;
const isDockLayout = ()=>(PageContainer?.classList.contains("CanvasImmersive") || IsPIP && PageContainer?.classList.contains("Exp_PopupDock")) ?? false;
let dockLiftWritten = null;
function writeDockLift(header, dockLift) {
    const value = dockLift.toString();
    if (dockLiftWritten?.el === header && dockLiftWritten.value === value) return;
    header.style.setProperty("--DockLift", value);
    dockLiftWritten = {
        el: header,
        value
    };
}
let canvasStage = null;
function getCanvasStage() {
    if (canvasStage?.isConnected && PageContainer?.contains(canvasStage)) return canvasStage;
    canvasStage = PageContainer?.querySelector(".ContentBox > .CanvasStage") ?? null;
    return canvasStage;
}
let visualsApplied = false;
let pageHover = false;
let mediaBoxHover = false;
let lastPageMouseMove;
const Page_MouseMove = ()=>{
    pageHover = true;
    lastPageMouseMove = performance.now();
    ToggleControls();
    if (!mediaBoxHover) {
        MouseMoveChecker();
    }
};
const MouseMoveChecker = ()=>{
    const now = performance.now();
    if (lastPageMouseMove !== undefined && now - lastPageMouseMove >= 750 && !mediaBoxHover) {
        animationLastTimestamp = now;
        ToggleControls(true);
        ControlsMaid.Clean("MouseMoveChecker");
        return;
    }
    ControlsMaid.Give(Scheduler.OnPreRender(MouseMoveChecker), "MouseMoveChecker");
};
const RunMediaBoxAnimation = ()=>{
    const timestampNow = performance.now();
    if (animationLastTimestamp !== undefined) {
        const deltaTime = (timestampNow - animationLastTimestamp) / 1000;
        const controlsOpacity = controlsOpacitySpring.Step(deltaTime);
        const artworkBrightness = artworkBrightnessSpring.Step(deltaTime);
        if (controlsOpacitySpring.GetGoal() > 0) {
            dockLiftSpring.SetGoal(1);
        } else if (controlsOpacity <= 0.005) {
            dockLiftSpring.SetGoal(0);
        }
        if (!isDockLayout()) dockLiftSpring.SetGoal(dockLiftSpring.GetGoal(), true);
        const dockLift = dockLiftSpring.Step(deltaTime);
        const MediaBox = PageContainer?.querySelector(".ContentBox .NowBar .Header .MediaBox");
        if (MediaBox) {
            MediaBox.style.setProperty("--ArtworkBrightness", artworkBrightness.toString());
            MediaBox.style.setProperty("--ControlsOpacity", controlsOpacity.toString());
            if (MediaBox.parentElement) writeDockLift(MediaBox.parentElement, dockLift);
        }
        getCanvasStage()?.style.setProperty("--StageBrightness", artworkBrightness.toString());
        if (controlsOpacitySpring.CanSleep() && artworkBrightnessSpring.CanSleep() && dockLiftSpring.CanSleep()) {
            animationLastTimestamp = undefined;
            visualsApplied = false;
            return;
        }
    }
    animationLastTimestamp = timestampNow;
    ControlsMaid.Give(Scheduler.OnPreRender(RunMediaBoxAnimation), "MediaBoxAnimation");
};
let controlsDragLock = false;
export const SetControlsDragLock = (locked)=>{
    if (controlsDragLock === locked) return;
    controlsDragLock = locked;
    if (!locked) ToggleControls(true);
};
const ToggleControls = (force = false)=>{
    if (controlsDragLock) return;
    const now = performance.now();
    const getControlsOpacityGoal = ()=>{
        if (lastPageMouseMove !== undefined && now - lastPageMouseMove >= 750) {
            return 0;
        } else if (pageHover && !mediaBoxHover) {
            return 0.65;
        } else if (mediaBoxHover) {
            return 0.985;
        } else {
            return 0;
        }
    };
    const getArtworkBrightnessGoal = ()=>{
        if (lastPageMouseMove !== undefined && now - lastPageMouseMove >= 750) {
            return 1;
        } else if (pageHover && !mediaBoxHover) {
            return 0.78;
        } else if (mediaBoxHover) {
            return 0.55;
        } else {
            return 1;
        }
    };
    const immersive = isDockLayout();
    for (const spring of [
        controlsOpacitySpring,
        artworkBrightnessSpring
    ]){
        spring.SetFrequency(immersive ? 2.5 : 2);
        spring.SetDampingRatio(immersive ? 1 : 2);
    }
    controlsOpacitySpring.SetGoal(getControlsOpacityGoal());
    artworkBrightnessSpring.SetGoal(getArtworkBrightnessGoal());
    if (force || visualsApplied === false) {
        visualsApplied = true;
        RunMediaBoxAnimation();
    }
};
let EventAbortController;
const MediaBox_MouseIn = ()=>{
    mediaBoxHover = true;
    pageHover = true;
    ToggleControls();
    ControlsMaid.Clean("MouseMoveChecker");
};
const MediaBox_MouseOut = ()=>{
    mediaBoxHover = false;
    pageHover = true;
    ToggleControls();
};
const MediaBox_MouseMove = ()=>{
    mediaBoxHover = true;
    pageHover = true;
    ControlsMaid.Clean("MouseMoveChecker");
    ToggleControls();
};
const Page_MouseIn = ()=>{
    mediaBoxHover = false;
    pageHover = true;
    ToggleControls();
};
const Page_MouseOut = ()=>{
    mediaBoxHover = false;
    pageHover = false;
    ToggleControls();
    ControlsMaid.Clean("MouseMoveChecker");
};
const HIDDEN_MAIN_STYLES = {
    "content-visibility": "hidden",
    position: "fixed",
    inset: "0"
};
function hideMainElement(mainElement) {
    for (const [property, value] of Object.entries(HIDDEN_MAIN_STYLES)){
        mainElement.style.setProperty(property, value);
    }
    SetKawarpSuspended("npvbg", true);
}
const NATIVE_CHROME_VARS = [
    "--NativeChromeMid",
    "--NativeChromeControlMax",
    "--NativeChromeLeftInset",
    "--NativeChromeRightInset"
];
function syncNativeChromeInsets(page) {
    const spacerIn = (row, edge)=>{
        const el = edge === "first" ? row?.firstElementChild : row?.lastElementChild;
        return el instanceof HTMLElement && el.childElementCount === 0 && el.offsetWidth > 0 ? el.getBoundingClientRect() : null;
    };
    const gapOf = (row)=>parseFloat(getComputedStyle(row).columnGap) || 0;
    const navBar = document.querySelector("#global-nav-bar");
    const leftRow = document.querySelector(".main-globalNav-historyButtonsWrapper");
    const rightRow = document.querySelector(".main-globalNav-contentRight");
    const left = spacerIn(leftRow, "first");
    const right = spacerIn(rightRow, "last");
    const values = {
        "--NativeChromeMid": null,
        "--NativeChromeControlMax": null,
        "--NativeChromeLeftInset": left && leftRow ? left.right + gapOf(leftRow) : null,
        "--NativeChromeRightInset": right && rightRow ? window.innerWidth - right.left + gapOf(rightRow) : null
    };
    if (navBar && leftRow && (left || right)) {
        const bar = navBar.getBoundingClientRect();
        values["--NativeChromeMid"] = bar.top + bar.height / 2;
        values["--NativeChromeControlMax"] = leftRow.getBoundingClientRect().height;
    }
    for (const name of NATIVE_CHROME_VARS){
        const value = values[name] === null ? "" : `${values[name]}px`;
        if (page.style.getPropertyValue(name) === value) continue;
        if (value) page.style.setProperty(name, value);
        else page.style.removeProperty(name);
    }
}
function clearNativeChromeInsets(page) {
    for (const name of NATIVE_CHROME_VARS)page.style.removeProperty(name);
}
function showMainElement() {
    SetKawarpSuspended("npvbg", false);
    const mainElement = document.querySelector("#main");
    if (!mainElement) return;
    for (const property of Object.keys(HIDDEN_MAIN_STYLES)){
        mainElement.style.removeProperty(property);
    }
}
export const ExitFullscreenElement = async ()=>{
    if (document.fullscreenElement) {
        await document.exitFullscreen();
    }
    setTimeout(Compactify, 1000);
};
export const EnterSpicyLyricsFullscreen = async ()=>{
    const mainElement = document.querySelector("#main");
    if (mainElement) {
        hideMainElement(mainElement);
    }
    try {
        if (!document.fullscreenElement) {
            await document.documentElement.requestFullscreen();
        }
    } catch (err) {
        const errorMessage = err instanceof Error ? err.message : String(err);
        console.error(`Fullscreen error: ${errorMessage}`);
    }
    document.documentElement.focus();
    setTimeout(Compactify, 1000);
};
function CleanupMediaBox() {
    EventAbortController?.abort();
    EventAbortController = undefined;
    ControlsMaid.CleanUp();
    animationLastTimestamp = undefined;
    lastPageMouseMove = undefined;
    visualsApplied = false;
    mediaBoxHover = false;
    pageHover = false;
    controlsDragLock = false;
}
let fullscreenGeneration = 0;
let closeInFlight = null;
export const IsFullscreenClosing = ()=>closeInFlight !== null;
function Open(skipDocumentFullscreen = false, moveElement = true) {
    const SpicyPage = PageContainer;
    const Root = document.body;
    const mainElement = document.querySelector("#main");
    const generation = ++fullscreenGeneration;
    closeInFlight = null;
    const stillOpen = ()=>Fullscreen.IsOpen && generation === fullscreenGeneration && PageContainer === SpicyPage;
    if (SpicyPage) {
        Fullscreen.IsOpen = true;
        Fullscreen.CinemaViewOpen = skipDocumentFullscreen;
        if (moveElement) TransferElement(SpicyPage, Root);
        SpicyPage.classList.add("Fullscreen");
        if (mainElement && moveElement) {
            hideMainElement(mainElement);
        }
        const nowBarToggle = Tooltips.NowBarToggle;
        if (nowBarToggle && typeof nowBarToggle.destroy === "function") {
            nowBarToggle.destroy();
        }
        const NowBarToggle = SpicyPage.querySelector(".ViewControls #NowBarToggle");
        if (NowBarToggle) {
            NowBarToggle.remove();
        }
        CleanUpNowBarComponents();
        CleanupMediaBox();
        OpenNowBar(true);
        const handleFullscreen = async ()=>{
            try {
                if (!skipDocumentFullscreen) {
                    await EnterSpicyLyricsFullscreen();
                }
                setTimeout(()=>PageView.AppendViewControls(true), 50);
            } catch (err) {
                const errorMessage = err instanceof Error ? err.message : String(err);
                console.error(`Fullscreen error: ${errorMessage}`);
            }
        };
        handleFullscreen();
        ResetLastLine();
        const MediaBox = SpicyPage.querySelector(".ContentBox .NowBar .Header .MediaBox");
        const MediaImageContainer = SpicyPage.querySelector(".ContentBox .NowBar .Header .MediaBox .MediaImageContainer");
        if (MediaBox && MediaImageContainer) {
            EventAbortController = new AbortController();
            const signal = EventAbortController.signal;
            MediaBox.addEventListener("mouseenter", MediaBox_MouseIn, {
                signal
            });
            MediaBox.addEventListener("mouseleave", MediaBox_MouseOut, {
                signal
            });
            MediaBox.addEventListener("mousemove", MediaBox_MouseMove, {
                signal
            });
            if (SpicyPage) {
                SpicyPage.addEventListener("mouseenter", Page_MouseIn, {
                    signal
                });
                SpicyPage.addEventListener("mousemove", Page_MouseMove, {
                    signal
                });
                SpicyPage.addEventListener("mouseleave", Page_MouseOut, {
                    signal
                });
            }
            if (!IsPIP) {
                syncNativeChromeInsets(SpicyPage);
                let syncFrame = null;
                const sync = ()=>{
                    if (syncFrame !== null) return;
                    syncFrame = requestCappedFrame(()=>{
                        syncFrame = null;
                        syncNativeChromeInsets(SpicyPage);
                    });
                };
                signal.addEventListener("abort", ()=>{
                    if (syncFrame !== null) cancelCappedFrame(syncFrame);
                });
                window.addEventListener("resize", sync, {
                    signal
                });
                const root = document.querySelector(".Root");
                if (root) {
                    let zoom = root.style.getPropertyValue("--zoom-level");
                    const zoomObserver = new MutationObserver(()=>{
                        const next = root.style.getPropertyValue("--zoom-level");
                        if (next === zoom) return;
                        zoom = next;
                        sync();
                    });
                    zoomObserver.observe(root, {
                        attributes: true,
                        attributeFilter: [
                            "style"
                        ]
                    });
                    signal.addEventListener("abort", ()=>zoomObserver.disconnect());
                }
            }
        }
        Global.Event.evoke("fullscreen:open", null);
    }
    setTimeout(()=>{
        if (IsPIP || !stillOpen()) return;
        Compactify();
        if ($forceCompactMode.get() && !IsCompactMode()) {
            SpicyPage?.classList.add("ForcedCompactMode");
            EnableCompactMode();
        }
    }, 750);
    setTimeout(()=>{
        if (!stillOpen()) return;
        PageView.AppendViewControls(true);
        SyncNoLyricsLayout();
    }, 75);
    GetCurrentLyricsContainerInstance()?.Resize();
}
function finishClose(SpicyPage, transfer) {
    if (transfer) {
        const root = GetPageRoot();
        if (root) {
            TransferElement(SpicyPage, root);
        } else {
            transfer = false;
            queueMicrotask(()=>void PageView.Destroy());
        }
    }
    SpicyPage.classList.remove("Fullscreen", "frame_F_Exit");
    clearNativeChromeInsets(SpicyPage);
    void ExitFullscreenElement().then(()=>{
        if (transfer) setTimeout(()=>PageView.AppendViewControls(true), 50);
    });
    SyncNoLyricsLayout();
    if (transfer && $currentLyricsData.get().includes("NO_LYRICS")) DeregisterNowBarBtn();
    ResetLastLine();
    if (!$isNowBarOpen.get()) {
        CloseNowBar();
    }
    CleanupMediaBox();
    CleanUpNowBarComponents();
    Global.Event.evoke("fullscreen:exit", null);
}
function Close(isPip = false) {
    if (closeInFlight) return closeInFlight;
    const SpicyPage = PageContainer;
    if (!SpicyPage) return Promise.resolve(false);
    const generation = ++fullscreenGeneration;
    Fullscreen.IsOpen = false;
    Fullscreen.CinemaViewOpen = false;
    if (isPip) {
        SpicyPage.classList.remove("Fullscreen");
        ResetLastLine();
        if (!$isNowBarOpen.get()) {
            CloseNowBar();
        }
        CleanupMediaBox();
        CleanUpNowBarComponents();
        Global.Event.evoke("fullscreen:exit", null);
        GetCurrentLyricsContainerInstance()?.Resize();
        return Promise.resolve(true);
    }
    showMainElement();
    SpicyPage.classList.add("frame_F_Exit");
    document.body.style.pointerEvents = "none";
    const run = async ()=>{
        try {
            await new Promise((r)=>setTimeout(r, 650));
        } finally{
            document.body.style.removeProperty("pointer-events");
        }
        if (generation !== fullscreenGeneration || PageContainer !== SpicyPage) {
            SpicyPage.classList.remove("frame_F_Exit");
            return false;
        }
        finishClose(SpicyPage, true);
        setTimeout(Compactify, 1000);
        GetCurrentLyricsContainerInstance()?.Resize();
        return true;
    };
    const promise = run().finally(()=>{
        if (closeInFlight === promise) closeInFlight = null;
    });
    closeInFlight = promise;
    return promise;
}
function CloseImmediately() {
    const SpicyPage = PageContainer;
    if (!SpicyPage || !Fullscreen.IsOpen && closeInFlight === null) return;
    ++fullscreenGeneration;
    closeInFlight = null;
    Fullscreen.IsOpen = false;
    Fullscreen.CinemaViewOpen = false;
    document.body.style.removeProperty("pointer-events");
    if (IsPIP) {
        SpicyPage.classList.remove("Fullscreen");
        CleanupMediaBox();
        CleanUpNowBarComponents();
        Global.Event.evoke("fullscreen:exit", null);
        return;
    }
    showMainElement();
    finishClose(SpicyPage, false);
}
function Toggle(skipDocumentFullscreen = false) {
    const SpicyPage = PageContainer;
    if (SpicyPage) {
        if (Fullscreen.IsOpen) {
            Close();
        } else {
            Open(skipDocumentFullscreen);
        }
    }
}
export { CleanupMediaBox };
export default Fullscreen;
