export default function TransferElement(element, targetContainer, index = -1) {
    if (!element || !targetContainer) {
        console.error("Both element and target container must be provided.");
        return;
    }
    try {
        if (index < 0 || index >= targetContainer.children.length) {
            targetContainer.appendChild(element);
        } else {
            targetContainer.insertBefore(element, targetContainer.children[index]);
        }
    } catch (error) {
        console.error("Error transferring element:", error);
    }
}
