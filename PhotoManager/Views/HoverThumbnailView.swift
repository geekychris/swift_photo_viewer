import SwiftUI
import AppKit

// Reusable thumbnail view wrapper that works with SwiftUI
struct ReusableHoverThumbnail: View {
    let photo: PhotoFile
    let size: CGFloat
    var onTap: (() -> Void)? = nil
    @EnvironmentObject var photoLibrary: PhotoLibrary
    @State private var thumbnailImage: NSImage?
    @State private var isHovering = false
    
    var body: some View {
        ThumbnailWithHoverWrapper(
            photo: photo,
            size: size,
            thumbnailImage: thumbnailImage,
            isHovering: $isHovering,
            photoLibrary: photoLibrary,
            onTap: onTap
        )
        .onAppear {
            thumbnailImage = photoLibrary.getThumbnailImage(for: photo)
        }
    }
}

struct ThumbnailWithHoverWrapper: NSViewRepresentable {
    let photo: PhotoFile
    let size: CGFloat
    let thumbnailImage: NSImage?
    @Binding var isHovering: Bool
    let photoLibrary: PhotoLibrary
    var onTap: (() -> Void)? = nil
    
    func makeNSView(context: Context) -> NSView {
        let containerView = AppKitHoverThumbnailView()
        containerView.photo = photo
        containerView.thumbnailImage = thumbnailImage
        containerView.photoLibrary = photoLibrary
        containerView.size = size
        containerView.isHoveringBinding = isHovering
        containerView.onTap = onTap
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let hoverView = nsView as? AppKitHoverThumbnailView {
            hoverView.thumbnailImage = thumbnailImage
            hoverView.onTap = onTap
        }
    }
}

class AppKitHoverThumbnailView: NSView {
    var photo: PhotoFile?
    var thumbnailImage: NSImage?
    var photoLibrary: PhotoLibrary?
    var size: CGFloat = 50
    var isHoveringBinding: Bool = false
    var onTap: (() -> Void)? = nil
    private var trackingArea: NSTrackingArea?
    private var popover: NSPopover?
    private var hoverTimer: Timer?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Add 0.5 second delay before showing popover
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.showPopover()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Cancel pending popover if mouse exits before delay
        hoverTimer?.invalidate()
        hoverTimer = nil
        hidePopover()
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onTap?()
    }
    
    private func showPopover() {
        guard let photo = photo, let photoLibrary = photoLibrary else { return }
        guard popover == nil else { return } // Don't show if already showing
        
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.contentViewController = HoverPreviewViewController(photo: photo, photoLibrary: photoLibrary)
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxX)
        self.popover = popover
    }
    
    private func hidePopover() {
        popover?.close()
        popover = nil
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        
        if let thumbnailImage = thumbnailImage {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            thumbnailImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.gray.withAlphaComponent(0.3).setFill()
            path.fill()
        }
        
        if isHoveringBinding {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: size, height: size)
    }
}

class HoverPreviewViewController: NSViewController {
    let photo: PhotoFile
    let photoLibrary: PhotoLibrary
    
    init(photo: PhotoFile, photoLibrary: PhotoLibrary) {
        self.photo = photo
        self.photoLibrary = photoLibrary
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 340))
        
        let imageView = NSImageView(frame: NSRect(x: 10, y: 40, width: 300, height: 300))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.2).cgColor
        
        // Load full image
        let fullPath = getFullPath(for: photo)
        print("Loading preview image from: \(fullPath)")
        
        if let fullImage = NSImage(contentsOfFile: fullPath) {
            print("Successfully loaded image: \(fullImage.size)")
            imageView.image = fullImage
        } else {
            print("Failed to load image from path")
            // Try getting from photoLibrary cache
            if let cachedImage = photoLibrary.getThumbnailImage(for: photo) {
                print("Using cached thumbnail instead")
                imageView.image = cachedImage
            }
        }
        
        let label = NSTextField(labelWithString: photo.fileName)
        label.frame = NSRect(x: 10, y: 10, width: 300, height: 20)
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        
        containerView.addSubview(imageView)
        containerView.addSubview(label)
        
        self.view = containerView
    }
    
    private func getFullPath(for photo: PhotoFile) -> String {
        let rootDir = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId })
        guard let rootPath = rootDir?.path else {
            print("No root path found for rootDirectoryId: \(photo.rootDirectoryId)")
            return photo.relativePath
        }
        return (rootPath as NSString).appendingPathComponent(photo.relativePath)
    }
}
