import Foundation
import AppKit
import PDFKit

class ContactSheetGenerator {
    private let photoLibrary: PhotoLibrary
    
    init(photoLibrary: PhotoLibrary) {
        self.photoLibrary = photoLibrary
    }
    
    // MARK: - HTML Generation
    
    func generateHTML(photos: [PhotoFile], title: String = "Contact Sheet") -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let exportDir = tempDir.appendingPathComponent("ContactSheet_\(UUID().uuidString)")
        let imagesDir = exportDir.appendingPathComponent("images")
        
        do {
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            
            var html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <title>\(title)</title>
                <style>
                    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; margin: 20px; background: #f5f5f5; }
                    h1 { text-align: center; color: #333; }
                    .info { text-align: center; color: #666; margin-bottom: 30px; }
                    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 20px; }
                    .photo-card { background: white; border-radius: 8px; padding: 15px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
                    .photo-card img { width: 100%; height: 300px; object-fit: cover; border-radius: 4px; }
                    .photo-info { margin-top: 10px; }
                    .photo-name { font-weight: bold; margin-bottom: 5px; word-break: break-all; }
                    .photo-meta { font-size: 0.9em; color: #666; line-height: 1.6; }
                    .rating { color: #ff9500; }
                    .color-tag { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 5px; }
                </style>
            </head>
            <body>
                <h1>\(title)</h1>
                <div class="info">Generated on \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)) • \(photos.count) photos</div>
                <div class="grid">
            """
            
            for (index, photo) in photos.enumerated() {
                // Copy image
                let imageName = "photo_\(index).jpg"
                let imageDestURL = imagesDir.appendingPathComponent(imageName)
                
                if let rootDirectory = photoLibrary.rootDirectories.first(where: { $0.id == photo.rootDirectoryId }) {
                    let sourcePath = (rootDirectory.path as NSString).appendingPathComponent(photo.relativePath)
                    let sourceURL = URL(fileURLWithPath: sourcePath)
                    
                    // Try to copy the actual image or use thumbnail
                    if FileManager.default.fileExists(atPath: sourcePath) {
                        try? FileManager.default.copyItem(at: sourceURL, to: imageDestURL)
                    } else if let thumbnail = photoLibrary.getThumbnailImage(for: photo) {
                        if let tiffData = thumbnail.tiffRepresentation,
                           let bitmapImage = NSBitmapImageRep(data: tiffData),
                           let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) {
                            try? jpegData.write(to: imageDestURL)
                        }
                    }
                }
                
                html += """
                <div class="photo-card">
                    <img src="images/\(imageName)" alt="\(photo.fileName)">
                    <div class="photo-info">
                        <div class="photo-name">\(photo.fileName)</div>
                        <div class="photo-meta">
                """
                
                if let width = photo.imageWidth, let height = photo.imageHeight {
                    html += "<div>\(width) × \(height)</div>"
                }
                
                if let dateTaken = photo.exifDateTaken {
                    let dateStr = DateFormatter.localizedString(from: dateTaken, dateStyle: .medium, timeStyle: .short)
                    html += "<div>📅 \(dateStr)</div>"
                }
                
                if let camera = photo.exifCameraModel {
                    html += "<div>📷 \(camera)</div>"
                }
                
                var exifParts: [String] = []
                if let aperture = photo.exifAperture {
                    exifParts.append("f/\(String(format: "%.1f", aperture))")
                }
                if let shutter = photo.exifShutterSpeed {
                    exifParts.append(shutter)
                }
                if let iso = photo.exifIso {
                    exifParts.append("ISO\(iso)")
                }
                if let focal = photo.exifFocalLength {
                    exifParts.append("\(Int(focal))mm")
                }
                if !exifParts.isEmpty {
                    html += "<div>\(exifParts.joined(separator: " • "))</div>"
                }
                
                if photo.rating > 0 {
                    let flags = String(repeating: "⚑", count: photo.rating)
                    html += "<div class=\"rating\">\(flags)</div>"
                }
                
                if let colorTag = photo.colorTag {
                    let colorMap: [String: String] = [
                        "red": "#ff3b30", "orange": "#ff9500", "yellow": "#ffcc00",
                        "green": "#34c759", "blue": "#007aff", "purple": "#af52de", "gray": "#8e8e93"
                    ]
                    if let colorHex = colorMap[colorTag] {
                        html += "<div><span class=\"color-tag\" style=\"background: \(colorHex);\"></span>\(colorTag.capitalized)</div>"
                    }
                }
                
                if let tags = photo.userTags, !tags.isEmpty {
                    html += "<div>🏷️ \(tags)</div>"
                }
                
                if let description = photo.userDescription, !description.isEmpty {
                    html += "<div style=\"margin-top: 8px; font-style: italic;\">\(description)</div>"
                }
                
                html += """
                        </div>
                    </div>
                </div>
                """
            }
            
            html += """
                </div>
            </body>
            </html>
            """
            
            let htmlFile = exportDir.appendingPathComponent("index.html")
            try html.write(to: htmlFile, atomically: true, encoding: .utf8)
            
            // Create a zip file
            let zipURL = tempDir.appendingPathComponent("ContactSheet.zip")
            try? FileManager.default.removeItem(at: zipURL)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-r", zipURL.path, exportDir.lastPathComponent]
            process.currentDirectoryURL = tempDir
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return zipURL
            }
            
            return htmlFile
        } catch {
            print("Error generating HTML: \(error)")
            return nil
        }
    }
    
    // MARK: - PDF Generation
    
    func generatePDF(photos: [PhotoFile], title: String = "Contact Sheet") -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let pdfURL = tempDir.appendingPathComponent("ContactSheet_\(UUID().uuidString).pdf")
        
        // Page setup
        let pageSize = CGSize(width: 612, height: 792) // US Letter
        let margin: CGFloat = 40
        let contentWidth = pageSize.width - (margin * 2)
        
        let columns = 3
        let spacing: CGFloat = 15
        let thumbnailWidth = (contentWidth - (spacing * CGFloat(columns - 1))) / CGFloat(columns)
        let thumbnailHeight = thumbnailWidth * 0.75
        let infoHeight: CGFloat = 100
        let cardHeight = thumbnailHeight + infoHeight + 10
        
        guard let pdfContext = CGContext(pdfURL as CFURL, mediaBox: nil, nil) else {
            return nil
        }
        
        var yPosition: CGFloat = margin
        var photoIndex = 0
        
        pdfContext.beginPDFPage(nil)
        
        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]
        let titleString = NSAttributedString(string: title, attributes: titleAttributes)
        titleString.draw(at: CGPoint(x: margin, y: pageSize.height - margin - 30))
        
        // Subtitle
        let subtitleText = "Generated on \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)) • \(photos.count) photos"
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.gray
        ]
        let subtitleString = NSAttributedString(string: subtitleText, attributes: subtitleAttributes)
        subtitleString.draw(at: CGPoint(x: margin, y: pageSize.height - margin - 50))
        
        yPosition = pageSize.height - margin - 80
        
        var column = 0
        
        for photo in photos {
            // Check if we need a new page
            if yPosition - cardHeight < margin {
                pdfContext.endPDFPage()
                pdfContext.beginPDFPage(nil)
                yPosition = pageSize.height - margin
                column = 0
            }
            
            let xPosition = margin + (CGFloat(column) * (thumbnailWidth + spacing))
            
            // Draw thumbnail
            let imageRect = CGRect(x: xPosition, y: yPosition - thumbnailHeight, width: thumbnailWidth, height: thumbnailHeight)
            
            if let thumbnail = photoLibrary.getThumbnailImage(for: photo) {
                let ctx = NSGraphicsContext(cgContext: pdfContext, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx
                
                thumbnail.draw(in: imageRect)
                
                NSGraphicsContext.restoreGraphicsState()
            } else {
                pdfContext.setFillColor(NSColor.lightGray.cgColor)
                pdfContext.fill(imageRect)
            }
            
            // Draw border
            pdfContext.setStrokeColor(NSColor.gray.cgColor)
            pdfContext.setLineWidth(0.5)
            pdfContext.stroke(imageRect)
            
            // Draw info
            var infoY = yPosition - thumbnailHeight - 5
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.black
            ]
            
            let fileName = NSAttributedString(string: photo.fileName, attributes: [
                .font: NSFont.boldSystemFont(ofSize: 10),
                .foregroundColor: NSColor.black
            ])
            fileName.draw(in: CGRect(x: xPosition, y: infoY, width: thumbnailWidth, height: 15))
            infoY -= 12
            
            if let width = photo.imageWidth, let height = photo.imageHeight {
                let dimText = NSAttributedString(string: "\(width) × \(height)", attributes: textAttributes)
                dimText.draw(at: CGPoint(x: xPosition, y: infoY))
                infoY -= 10
            }
            
            if let camera = photo.exifCameraModel {
                let cameraText = NSAttributedString(string: camera, attributes: textAttributes)
                cameraText.draw(in: CGRect(x: xPosition, y: infoY, width: thumbnailWidth, height: 10))
                infoY -= 10
            }
            
            column += 1
            if column >= columns {
                column = 0
                yPosition -= cardHeight + spacing
            }
            
            photoIndex += 1
        }
        
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        
        return pdfURL
    }
}
