//
//  StickyScrollView.swift
//  LingCode
//
//  SMOOTH STREAMING FIX: 60 FPS sticky scroll using NSScrollView
//  Replaces SwiftUI's ScrollView for buttery smooth auto-scroll during streaming
//

import SwiftUI
import AppKit

/// NSScrollView wrapper for 60 FPS sticky scroll to bottom
struct StickyScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    @Binding var shouldAutoScroll: Bool
    let onScrollChange: ((CGFloat) -> Void)?
    
    init(shouldAutoScroll: Binding<Bool> = .constant(true), onScrollChange: ((CGFloat) -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self._shouldAutoScroll = shouldAutoScroll
        self.onScrollChange = onScrollChange
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let hostingView = NSHostingView(rootView: content)
        
        scrollView.documentView = hostingView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // SMOOTH STREAMING FIX: Enable smooth scrolling
        scrollView.scrollerStyle = .overlay
        
        context.coordinator.scrollView = scrollView
        context.coordinator.hostingView = hostingView
        
        // Setup scroll observation
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Update hosting view content
        if let hostingView = context.coordinator.hostingView {
            hostingView.rootView = content
            hostingView.invalidateIntrinsicContentSize()
        }
        
        // SMOOTH STREAMING FIX: Sticky scroll to bottom at 60 FPS
        if shouldAutoScroll {
            context.coordinator.scrollToBottom()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(shouldAutoScroll: $shouldAutoScroll, onScrollChange: onScrollChange)
    }
    
    class Coordinator: NSObject {
        var scrollView: NSScrollView?
        var hostingView: NSHostingView<Content>?
        @Binding var shouldAutoScroll: Bool
        let onScrollChange: ((CGFloat) -> Void)?
        private var lastScrollPosition: CGFloat = 0
        
        init(shouldAutoScroll: Binding<Bool>, onScrollChange: ((CGFloat) -> Void)?) {
            self._shouldAutoScroll = shouldAutoScroll
            self.onScrollChange = onScrollChange
        }
        
        /// SMOOTH STREAMING FIX: Scroll to bottom with sticky physics (locks viewport to bottom pixel)
        func scrollToBottom() {
            guard let scrollView = scrollView,
                  let documentView = scrollView.documentView else { return }
            
            let contentHeight = documentView.bounds.height
            let visibleHeight = scrollView.contentView.bounds.height
            
            // Calculate bottom position
            let bottomY = max(0, contentHeight - visibleHeight)
            
            // SMOOTH STREAMING FIX: Use NSClipView's scrollToPoint for smooth 60 FPS scrolling
            // This locks the viewport to the bottom pixel, making text push up smoothly
            let point = NSPoint(x: 0, y: bottomY)
            scrollView.contentView.scroll(to: point)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        
        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView = scrollView,
                  let documentView = scrollView.documentView else { return }
            
            let contentHeight = documentView.bounds.height
            let visibleHeight = scrollView.contentView.bounds.height
            let scrollPosition = scrollView.contentView.bounds.origin.y
            let maxScroll = max(0, contentHeight - visibleHeight)
            
            // Calculate scroll percentage (0 = top, 1 = bottom)
            let scrollPercentage = maxScroll > 0 ? scrollPosition / maxScroll : 1.0
            
            // Detect if user scrolled up (disable auto-scroll)
            if scrollPosition < lastScrollPosition - 10 {
                // User scrolled up significantly
                shouldAutoScroll = false
            } else if scrollPercentage > 0.95 {
                // Near bottom, re-enable auto-scroll
                shouldAutoScroll = true
            }
            
            lastScrollPosition = scrollPosition
            onScrollChange?(scrollPercentage)
        }
    }
}
