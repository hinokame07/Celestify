export default {Event:{evoke(name,detail){window.dispatchEvent(new CustomEvent(name,{detail}))}}};
