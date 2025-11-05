# PhotoManager

A comprehensive photo management application for macOS built with Swift and SwiftUI. PhotoManager helps you organize, browse, and manage large photo collections with advanced features like duplicate detection, EXIF data extraction, and hierarchical browsing.

## Features

### Core Functionality
- **Directory Management**: Add and manage root directories containing your photo collections
- **Recursive Scanning**: Automatically scan directories and subdirectories for image files
- **EXIF Data Extraction**: Extract and display comprehensive metadata from photos
- **File Hashing**: Calculate SHA256 hashes for each file to enable duplicate detection
- **Thumbnail Generation**: Generate and cache thumbnails for fast browsing

### Browsing Modes
- **Directory View**: Browse photos organized by their actual directory structure
- **Timeline View**: Browse photos organized by year/month/day using EXIF date information
- **Duplicate View**: Find and manage duplicate photos across your collection

### Advanced Features
- **Duplicate Detection**: Hash-based duplicate detection with space savings calculations
- **Infinite Scroll**: Lazy loading for performance with large photo collections
- **Full Image Viewer**: Click thumbnails to view full-resolution images with EXIF data
- **Rescan Support**: Keep database in sync by rescanning directories
- **SQLite Database**: Robust local database storage

## Supported File Formats

- JPEG (.jpg, .jpeg)
- PNG (.png)
- TIFF (.tiff, .tif)
- HEIC/HEIF (.heic, .heif)
- RAW formats (.raw, .cr2, .nef, .arw, .dng, .orf, .rw2)

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Building the Application

### Using Xcode (Recommended)
1. Open the `PhotoManager.xcodeproj` file in Xcode
2. Wait for Swift Package Manager to resolve dependencies (SQLite.swift)
3. Select the PhotoManager target and your desired scheme
4. Build and run the application using Cmd+R

### Project Structure
The project is organized as a standard Xcode macOS application:
- `PhotoManager/` - Main source code directory
- `PhotoManager.xcodeproj/` - Xcode project file
- `Package.swift` - Swift Package Manager configuration (for dependencies)
- `README.md` - This file

## Usage

### Getting Started

1. **Launch PhotoManager**
   - The application will create its database and thumbnail directory automatically
   - Database: `~/Library/Application Support/PhotoManager/PhotoManager.sqlite`
   - Thumbnails: `~/Library/Application Support/PhotoManager/Thumbnails/`

2. **Add Photo Directories**
   - Click the "+" button in the sidebar
   - Select a directory containing your photos
   - The directory will be added to your root directories list

3. **Scan Directories**
   - Click the refresh icon next to any directory to scan it
   - PhotoManager will recursively scan for image files
   - EXIF data extraction and thumbnail generation happen automatically

### Browsing Your Photos

#### Directory Mode
- View photos organized by their actual directory structure
- Expand directories to see subdirectories and photo counts
- Click on any directory to view its photos in the main grid

#### Timeline Mode
- Photos are organized by year and month using EXIF date information
- Expand years to see months with photo counts
- Small thumbnail previews show a sample of photos in each month

#### Duplicates Mode
- View groups of duplicate photos found by hash comparison
- See wasted space calculations for each duplicate group
- Click to expand groups and see all duplicate locations
- Delete duplicates from the database (files remain on disk)

### Photo Viewing
- Click any thumbnail to open the full photo viewer
- View full-resolution images with zoom and scroll
- Detailed EXIF metadata panel shows:
  - File information (name, size, dimensions, path)
  - Camera information (model, lens)
  - Exposure data (aperture, shutter speed, ISO, focal length)
  - Date information (taken, created, modified)
  - Technical data (file hash, thumbnail status)

### Rescanning
- Use the refresh button next to directories to rescan
- Rescanning updates the database with new or changed files
- Removes database entries for deleted files
- Regenerates thumbnails as needed

## Project Structure

```
Sources/PhotoManager/
├── main.swift                          # Application entry point
├── Models/
│   └── DatabaseModels.swift           # Data models and database schema
├── Services/
│   ├── DatabaseManager.swift          # SQLite database operations
│   ├── FileScanningService.swift      # File scanning and EXIF extraction
│   ├── ThumbnailService.swift         # Thumbnail generation and management
│   └── PhotoLibrary.swift            # Main service coordinator
└── Views/
    ├── ContentView.swift              # Main application UI
    ├── DirectorySidebarView.swift     # Directory browsing sidebar
    ├── TimelineSidebarView.swift      # Date-based browsing sidebar
    ├── DuplicatesSidebarView.swift    # Duplicate detection interface
    ├── PhotoGridView.swift            # Main photo grid with infinite scroll
    ├── PhotoDetailView.swift          # Full photo viewer with EXIF display
    └── SettingsView.swift             # Application settings
```

## Database Schema

The application uses SQLite with the following main tables:

### root_directories
- Stores managed photo directory paths
- Tracks last scan times
- Manages active/inactive states

### photo_files
- Complete photo metadata for each file
- EXIF data fields (camera, lens, exposure settings)
- File hash for duplicate detection
- Thumbnail management flags
- Foreign key relationship to root directories

## Architecture Notes

- **SwiftUI**: Modern declarative UI framework
- **Combine**: Reactive data binding with @Published properties
- **SQLite.swift**: Type-safe database operations
- **ImageIO**: Native macOS image processing for EXIF and thumbnails
- **CryptoKit**: Secure hash calculation for duplicate detection
- **Async/Await**: Modern Swift concurrency for file operations

## Performance Considerations

- **Lazy Loading**: Photos are loaded in batches of 50 for smooth scrolling
- **Background Processing**: File scanning and thumbnail generation happen off the main thread
- **Database Indexing**: Optimized queries with proper indices on frequently searched fields
- **Thumbnail Caching**: Generated thumbnails are cached to disk for fast subsequent access

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure PhotoManager has permission to access your photo directories
   - Grant Full Disk Access if needed in System Preferences → Security & Privacy

2. **Large Collections**
   - Initial scanning of large directories may take time
   - Thumbnail generation is progressive and happens in the background

3. **RAW File Support**
   - RAW file support depends on macOS system codecs
   - Some proprietary RAW formats may not be supported

### Logs and Debugging
- Check Console app for PhotoManager logs
- Database issues are logged to the console
- File scanning progress is displayed in the UI status area

## Future Enhancements

Potential improvements for future versions:
- Tags and keyword management
- Advanced search and filtering
- Photo editing integration
- Export and sharing features
- Cloud storage integration
- Batch operations for duplicates
- Custom thumbnail sizes
- Database backup and restore

## License

This project is provided as-is for educational and personal use.