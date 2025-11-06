import SwiftUI
import AppKit

struct ResizableSplitView<SidebarContent: View, DetailContent: View>: NSViewRepresentable {
    let sidebar: SidebarContent
    let detail: DetailContent
    let minSidebarWidth: CGFloat
    let maxSidebarWidth: CGFloat
    @Binding var sidebarWidth: CGFloat
    
    init(minSidebarWidth: CGFloat = 300,
         maxSidebarWidth: CGFloat = 1000,
         sidebarWidth: Binding<CGFloat>,
         @ViewBuilder sidebar: () -> SidebarContent,
         @ViewBuilder detail: () -> DetailContent) {
        self.minSidebarWidth = minSidebarWidth
        self.maxSidebarWidth = maxSidebarWidth
        self._sidebarWidth = sidebarWidth
        self.sidebar = sidebar()
        self.detail = detail()
    }
    
    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        
        // Create sidebar with frame tracking
        let sidebarHosting = NSHostingController(rootView: sidebar)
        sidebarHosting.sizingOptions = [.intrinsicContentSize]
        let sidebarView = sidebarHosting.view
        splitView.addArrangedSubview(sidebarView)
        
        // Create detail
        let detailHosting = NSHostingController(rootView: detail)
        detailHosting.sizingOptions = [.intrinsicContentSize]
        let detailView = detailHosting.view
        splitView.addArrangedSubview(detailView)
        
        // Store hosting controllers to prevent deallocation
        context.coordinator.sidebarController = sidebarHosting
        context.coordinator.detailController = detailHosting
        
        // Set initial width
        splitView.setPosition(500, ofDividerAt: 0)
        
        return splitView
    }
    
    func updateNSView(_ splitView: NSSplitView, context: Context) {
        // Update the views
        context.coordinator.sidebarController?.rootView = sidebar
        context.coordinator.detailController?.rootView = detail
        
        // Force layout update
        splitView.needsLayout = true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(minWidth: minSidebarWidth, maxWidth: maxSidebarWidth, sidebarWidth: $sidebarWidth)
    }
    
    class Coordinator: NSObject, NSSplitViewDelegate {
        var sidebarController: NSHostingController<SidebarContent>?
        var detailController: NSHostingController<DetailContent>?
        let minWidth: CGFloat
        let maxWidth: CGFloat
        @Binding var sidebarWidth: CGFloat
        
        init(minWidth: CGFloat, maxWidth: CGFloat, sidebarWidth: Binding<CGFloat>) {
            self.minWidth = minWidth
            self.maxWidth = maxWidth
            self._sidebarWidth = sidebarWidth
        }
        
        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return minWidth
        }
        
        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return maxWidth
        }
        
        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            return false
        }
        
        func splitViewDidResizeSubviews(_ notification: Notification) {
            // Update the sidebar width binding
            if let splitView = notification.object as? NSSplitView,
               let sidebarView = splitView.arrangedSubviews.first {
                DispatchQueue.main.async {
                    self.sidebarWidth = sidebarView.frame.width
                }
            }
        }
    }
}
