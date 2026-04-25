//
//  NotchViewController.swift
//  VibePulse
//
//  Hosts the SwiftUI NotchView with click-through support (adapted from Vibe Notch)
//

import AppKit
import SwiftUI

class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitTestRect().contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }
}

class NotchViewController: NSViewController {
    private let viewModel: NotchViewModel
    private var hostingView: PassThroughHostingView<NotchView>!

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        hostingView = PassThroughHostingView(rootView: NotchView(viewModel: viewModel))

        hostingView.hitTestRect = { [weak self] in
            guard let self = self else { return .zero }
            let vm = self.viewModel
            let geometry = vm.geometry
            let windowHeight = geometry.windowHeight

            switch vm.status {
            case .opened:
                let panelSize = vm.openedSize
                let panelWidth = panelSize.width + 52
                let panelHeight = panelSize.height
                let screenWidth = geometry.screenRect.width
                return CGRect(
                    x: (screenWidth - panelWidth) / 2,
                    y: windowHeight - panelHeight,
                    width: panelWidth,
                    height: panelHeight
                )
            case .closed, .popping:
                let notchRect = geometry.deviceNotchRect
                let screenWidth = geometry.screenRect.width
                return CGRect(
                    x: (screenWidth - notchRect.width) / 2 - 10,
                    y: windowHeight - notchRect.height - 5,
                    width: notchRect.width + 20,
                    height: notchRect.height + 10
                )
            }
        }

        self.view = hostingView
    }
}
