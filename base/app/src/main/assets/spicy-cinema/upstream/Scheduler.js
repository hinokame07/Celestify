const SchedulerEnums = {
    timeout: 0,
    interval: 1,
    raf: 2
};
const Timeout = (cb, ms)=>[
        SchedulerEnums.timeout,
        window.setTimeout(cb, ms),
        {
            cancelled: false
        }
    ];
const Interval = (cb, ms)=>[
        SchedulerEnums.interval,
        window.setInterval(cb, ms),
        {
            cancelled: false
        }
    ];
const OnPreRender = (cb)=>[
        SchedulerEnums.raf,
        requestAnimationFrame(cb),
        {
            cancelled: false
        }
    ];
const Cancel = (scheduledItems)=>{
    const normalizedItems = Array.isArray(scheduledItems[0]) ? scheduledItems : [
        scheduledItems
    ];
    for (const scheduledItem of normalizedItems){
        const [type, id, dataObject] = scheduledItem;
        if (dataObject.cancelled) continue;
        dataObject.cancelled = true;
        if (type === SchedulerEnums.timeout) window.clearTimeout(id);
        else if (type === SchedulerEnums.interval) window.clearInterval(id);
        else if (type === SchedulerEnums.raf) cancelAnimationFrame(id);
    }
};
const IsScheduled = (value)=>Array.isArray(value) && value.length === 3 && typeof value[0] === "number" && typeof value[1] === "number" && typeof value[2] === "object";
const Scheduler = {
    Timeout,
    Interval,
    OnPreRender,
    Cancel,
    IsScheduled
};
export default Scheduler;
