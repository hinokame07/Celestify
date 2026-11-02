import Scheduler from "./Scheduler.js";
function uuidv4() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c)=>{
        const r = Math.random() * 16 | 0;
        return (c === "x" ? r : r & 0x3 | 0x8).toString(16);
    });
}
function cleanItem(item) {
    if (typeof item === "function") {
        item();
    } else if (item instanceof MutationObserver || item instanceof ResizeObserver) {
        item.disconnect();
    } else if (item instanceof Element) {
        item.remove();
    } else if (Scheduler.IsScheduled(item)) {
        Scheduler.Cancel(item);
    } else if (typeof item === "object" && item !== null && "Destroy" in item && typeof item.Destroy === "function") {
        item.Destroy();
    } else {
        console.warn("[Maid] Unknown item type — cannot clean:", item);
    }
}
export class Maid {
    _items = new Map();
    _destroyed = false;
    Give(item, key) {
        const k = key ?? uuidv4();
        if (this._destroyed) {
            cleanItem(item);
            return item;
        }
        if (this._items.has(k)) {
            cleanItem(this._items.get(k));
        }
        this._items.set(k, item);
        return item;
    }
    GiveItems(...items) {
        for (const item of items)this.Give(item);
        return items;
    }
    Get(key) {
        return this._items.get(key);
    }
    Has(key) {
        return this._items.has(key);
    }
    Clean(key) {
        const item = this._items.get(key);
        if (item === undefined) return;
        this._items.delete(key);
        cleanItem(item);
    }
    CleanUp() {
        for (const item of this._items.values())cleanItem(item);
        this._items.clear();
    }
    Destroy() {
        this.CleanUp();
        this._destroyed = true;
    }
    IsDestroyed() {
        return this._destroyed;
    }
}
