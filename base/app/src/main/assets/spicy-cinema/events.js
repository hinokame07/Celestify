// The Android dialog owns this isolated document. There is no global Spotify Desktop event bus.
export default {
  Event: {
    listen(name, fn) {
      window.addEventListener(name, fn);
    },
    evoke(name) {
      window.dispatchEvent(new Event(name));
    },
  },
};
