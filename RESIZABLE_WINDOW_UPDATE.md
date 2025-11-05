# Resizable Timeline Grid Window Update

## Changes Made

### 1. Updated Deployment Target
- **Changed from**: macOS 14.0
- **Changed to**: macOS 15.0
- **Reason**: Required for `.presentationSizing()` modifier that enables window resizability

### 2. Added Presentation Sizing Modifier
Added `.presentationSizing(.fitted)` to the timeline photo grid sheet, which:
- Enables **true window resizing** by dragging edges/corners
- Allows the window to adapt to its content size
- Provides native macOS window resize behavior

### 3. Improved Window Layout
Updated `TimelinePhotoGridSheet`:
- Replaced `NavigationStack` with direct `VStack` for cleaner layout
- Added custom toolbar with title and Done button
- Set flexible frame constraints:
  - **Min size**: 500×400 pixels
  - **Ideal size**: 900×700 pixels  
  - **Max size**: Unlimited (fills available space)

### 4. Enhanced Thumbnail Control
The window now includes:
- ✅ **Resizable window** - Drag edges/corners to resize
- ✅ **Thumbnail size slider** - Zoom in/out from 80px to 300px
- ✅ **Responsive grid** - Automatically adjusts columns based on window and thumbnail size

## Usage

When viewing photos in the Timeline view:
1. Click the **plus button** (`+[number]`) in any time period
2. A **resizable window** opens showing all photos
3. **Resize the window** by dragging any edge or corner
4. **Adjust thumbnail size** using the slider at the top
5. Click **Done** to close

## Technical Details

### Files Modified
- `PhotoManager.xcodeproj/project.pbxproj` - Deployment target update
- `PhotoManager/Views/TimelineSidebarView.swift` - Added presentation sizing and improved layout

### macOS 15.0 Features Used
- `.presentationSizing(.fitted)` - Enables window resizability
- Frame constraints with `.infinity` - Allows unlimited growth

### Backward Compatibility
⚠️ **Requires macOS 15.0 or later** to run the application.

## Benefits

1. **Better User Experience**: Users can size the window to their preference
2. **Flexible Workflow**: Resize to view more/fewer photos at once
3. **Multi-Monitor Support**: Can expand window across large displays
4. **Consistent with macOS**: Uses native window resizing behavior
5. **Dual Control**: Independent control over window size and thumbnail zoom

## Build Status
✅ **Build Successful** with macOS 15.0 deployment target
