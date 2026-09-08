# Optional extended history

The default retention limit remains 200. Storage settings keep an editable limit and an Apply button. Enable **extended history** to enter limits above 1,000 or **-1** for unlimited retention. Invalid values do not save. Reducing a limit requires confirmation because excess unpinned records are permanently removed in the selected sort order. Pins do not count toward the limit.

The display cache contains the 1,000 most recently copied unpinned records plus pins. Typing searches that cache using the existing search mode. With extended history disabled, the popup has no archive controls. Turning the toggle off leaves the saved retention limit and records unchanged, including an existing unlimited limit; re-enable it to edit that limit or retrieve older records.

**Deep search** explicitly queries all stored titles/OCR summaries in a background SwiftData context, using case-insensitive substring matching and pages of 100. It does not search every byte of long clips. **Next page** replaces the current page; **Recent**, editing the query, closing the popup, recording a new clipboard item or disabling extended history exits archive search.

Cache eviction releases UI objects without deleting records. Finite retention removes excess records independently of the cache; unlimited retention does not prune. Copying a cold record preserves its original and creates a recent copy; recent-record deduplication remains. Explicit Delete/Clear/Clear all/Clear on quit retain their existing behavior.

The original database and schema are retained. Legacy titles are sanitized only for display, and startup orphan cleanup is not run, preserving existing data without loading the entire archive at startup.

## Verification

The history regressions cover persistence beyond 1,000 records, finite retention, archive pagination, pinning, selection synchronization, copying while recording is paused, and decorator release. For native UI verification, launch a Debug build with `enable-testing seed-archive-history`; it uses an in-memory store with 1,205 synthetic records, including 205 older records matching `Archive-only`.
