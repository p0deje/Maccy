# Maccy Tabs Feature

## Feature Overview

This version of Maccy introduces an optional Tabs feature that provides separate views for history and pinned items, enhancing organization and workflow.

### Key Features

- **Tab-based Separation**: The "History" tab displays only copied items (excluding pins), while the "Pinned" tab exclusively shows pinned items.
- **Optional Functionality**: The Tabs feature can be easily enabled or disabled in the "Behavior" section of the app's settings.
- **Tab Key Navigation**: Users can press the `Tab` key to cycle between the "History" and "Pinned" tabs.
- **Window Size Persistence**: The application remembers any manually adjusted window dimensions and restores them on the next launch. This includes both height and width.
- **Smart Sizing Behavior**: The window size is no longer reset after searching or selecting an item. It will only expand automatically if the content requires more space.
- **Default Experience**: To maintain the classic user experience, the Tabs feature is disabled by default.

### How to Use

1.  **Enable the Feature**:
    *   Open Settings (`⌘,`).
    *   Navigate to the "Behavior" section.
    *   Check the "Enable tabs" option.

2.  **Using Tabs**:
    *   Once enabled, "History" and "Pinned" tabs will appear below the search bar.
    *   The "History" tab contains all copied items, excluding those that are pinned.
    *   The "Pinned" tab contains only pinned items.

### Technical Summary

- Based on Maccy v2.5.1.
- Implements a new tabbed interface to separate history and pinned items.
- The tab bar's UI seamlessly integrates with the main window's blur effect.
- Enhances window management by making its size persistent and not resetting it after common actions.
- Compatible with macOS 11.0+.
