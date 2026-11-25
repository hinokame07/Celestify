//
//  HapticsManager.swift
//  Celestify
//
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import UIKit

@MainActor
public final class HapticsManager {
    public static let shared = HapticsManager()

    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        selectionGenerator.prepare()
        softImpact.prepare()
    }

    public func selection() {
        selectionGenerator.selectionChanged()
    }

    public func tap() {
        lightImpact.impactOccurred(intensity: 0.75)
    }

    public func softDetent() {
        softImpact.impactOccurred(intensity: 0.8)
    }

    public func scrubBoundary() {
        rigidImpact.impactOccurred(intensity: 0.85)
    }

    public func emphasize() {
        mediumImpact.impactOccurred()
    }

    public func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
    }
}
