// NotchViewModel.swift
// View model for notch state and animations

import Combine
import NotchwatchKit
import SwiftUI

enum NotchState {
    case closed
    case open
    case peeking
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var notchState: NotchState = .closed
    @Published private(set) var geometry: NotchGeometry
    @Published var notchSize: CGSize

    /// The closed shape: the cut-out itself, nothing more.
    var closedNotchSize: CGSize {
        geometry.closedSize
    }

    /// Size of the window hosting the panel, shadow included.
    var windowSize: CGSize {
        geometry.windowFrame.size
    }

    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private var peekTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Built by the coordinator, which owns it: the panel's state has to outlive
    /// the view, so that `--panel` is answerable whenever the process is up.
    init(coordinator: UICoordinator) {
        let geometry = coordinator.geometry ?? .none
        self.geometry = geometry
        notchSize = geometry.closedSize

        // Plugging in a display, switching resolution or closing the lid resizes
        // the cut-out under a running panel. The coordinator republishes on the
        // screen-parameter notification and the panel follows, instead of keeping
        // the sizes it happened to be born with.
        coordinator.$geometry
            .compactMap { $0 }
            .sink { [weak self] geometry in
                self?.apply(geometry)
            }
            .store(in: &cancellables)
    }

    func open() {
        peekTask?.cancel()
        notchState = .open
        withAnimation(animationSpring) {
            notchSize = geometry.panelSize
        }
    }

    func close() {
        peekTask?.cancel()
        withAnimation(animationSpring) {
            notchSize = geometry.closedSize
            notchState = .closed
        }
    }

    func toggle() {
        if notchState == .open {
            close()
        } else {
            open()
        }
    }

    /// Briefly expand the notch to show a notification, then return to closed state
    func peek(duration: TimeInterval = 2.0) {
        guard notchState == .closed else { return }

        peekTask?.cancel()
        notchState = .peeking

        withAnimation(animationSpring) {
            notchSize = geometry.peekSize
        }

        peekTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(animationSpring) {
                    notchSize = geometry.closedSize
                    notchState = .closed
                }
            }
        }
    }

    private func apply(_ geometry: NotchGeometry) {
        guard geometry != self.geometry else { return }
        self.geometry = geometry

        withAnimation(animationSpring) {
            switch notchState {
            case .closed: notchSize = geometry.closedSize
            case .open: notchSize = geometry.panelSize
            case .peeking: notchSize = geometry.peekSize
            }
        }
    }
}
