# Release Notes Draft

## v2.9.2-beta (TBD)

### Bug Fixes

#### Audiobooks
- **Fixed audiobooks not loading after provider re-add**: When removing and re-adding an AudiobookShelf provider, the app would show 0 audiobooks because saved library paths referenced the old provider instance ID. Now automatically clears stale settings and falls back to the library_items API.

- **Fixed duplicate provider filter options**: After re-adding a provider, two entries for the same provider could appear in the library filter menu. Now deduplicates providers by name, keeping the one with more items.

- **Fixed multiple accounts of same service not showing**: When you have multiple accounts of the same service (e.g., two Spotify accounts for different family members), only one would appear in the library menu provider toggles. Now all accounts with distinct names are shown.

- **Fixed audiobook year sorting**: Sort by year now works correctly for audiobooks. Fixed two issues:
  - Year data is now properly extracted from ABS's `metadata.release_date` field (handles both "2024" and "2024-01-15" formats)
  - Sort handler now properly supports ascending and descending year sorts

#### Library Sorting
- **Fixed letter scrollbar showing irrelevant letters**: When sorting by date or play count, the scrollbar popup now hides instead of showing meaningless letters. Shows contextual info based on sort type (letters for alphabetical, years for year sort, hidden for date/count sorts).

- **Fixed sorting not working for date added, last played, play count**: These sort options now correctly preserve server-side sorting instead of re-sorting alphabetically on the client. Affected albums, artists, and tracks tabs.

- **Fixed playlists sorting**: Modified, last played, and play count sorting now works for playlists by properly requesting sorted data from the server.

- **Fixed ascending/descending not working**: Sort direction now properly applies for all sort types across albums, artists, playlists, and audiobooks.

- **Fixed list not updating when sort order changes**: Added sort order to ListView/GridView keys to force UI rebuilds when changing sort direction.

#### Provider Management
- **Fixed stale provider IDs persisting in settings**: When toggling providers, stale provider instance IDs (from removed providers) are now automatically cleaned up from saved settings.

### Technical Changes
- Added `ScrollbarDisplayMode` enum (`letter`, `year`, `count`, `none`) for contextual scrollbar popups
- Added `updateCachedAlbums()`, `updateCachedArtists()`, `updateCachedPlaylists()` methods to SyncService for proper cache synchronization with sorted data
- Provider filter now validates against available providers when toggling, not just on initial load
- Removed Selector caching from albums and artists tabs to ensure proper rebuilds when source tracking updates
- Options menu provider toggles now use Consumer to watch Provider state directly
