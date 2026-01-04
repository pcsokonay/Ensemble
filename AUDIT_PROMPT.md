# Ensemble Codebase Audit Prompt

Run this prompt with Claude Code to perform a comprehensive audit of the Ensemble Flutter app.

---

## Prompt

You are performing a comprehensive code audit on the Ensemble Flutter app. This is a music/audiobook/podcast player app with 93+ Dart files.

**CRITICAL RULES:**
1. DO NOT remove or break any existing functionality
2. All changes must be on the current branch: `audit/code-quality-review`
3. Run `flutter analyze` after each set of changes to verify no regressions
4. Commit changes in logical, reviewable chunks

**AUDIT PHASES:**

### Phase 1: Code Quality Analysis (Read-Only)
First, analyze the codebase without making changes. Create a report covering:

1. **Large File Analysis** - Review these files for refactoring opportunities:
   - `lib/screens/new_library_screen.dart` (122KB)
   - `lib/screens/search_screen.dart` (129KB)
   - `lib/widgets/expandable_player.dart` (107KB)
   - `lib/screens/album_details_screen.dart` (48KB)
   - `lib/screens/artist_details_screen.dart` (45KB)

2. **Pattern Inconsistencies** - Look for:
   - Inconsistent naming conventions (camelCase vs snake_case)
   - Mixed widget composition patterns
   - Inconsistent error handling approaches
   - Duplicate code across screens/widgets

3. **Performance Red Flags** - Identify:
   - Unnecessary rebuilds (missing const constructors)
   - Heavy computations in build methods
   - Missing list item caching (ListView.builder vs ListView)
   - Inefficient state management patterns

4. **Scroll Performance Issues** - Specifically audit:
   - ScrollController usage and disposal
   - Sliver implementations
   - AnimatedBuilder/AnimatedWidget usage
   - Image loading in scrollable lists
   - Any jank-inducing patterns

### Phase 2: Quick Wins (Low Risk, High Impact)
Apply these fixes first:

1. Add missing `const` constructors throughout
2. Fix any `flutter analyze` warnings
3. Remove dead code and unused imports
4. Standardize formatting with `dart format`

### Phase 3: Scroll Animation Optimization
Focus on smoother scrolling:

1. **Image Optimization**
   - Ensure CachedNetworkImage is used consistently
   - Add appropriate cacheWidth/cacheHeight
   - Implement proper placeholder/error widgets

2. **List Performance**
   - Convert any ListView to ListView.builder where appropriate
   - Add itemExtent where possible for fixed-height items
   - Implement AutomaticKeepAliveClientMixin where needed
   - Consider RepaintBoundary for complex list items

3. **Animation Smoothing**
   - Use `Curves.easeOutCubic` or similar for scroll-linked animations
   - Ensure animations run at 60fps (avoid heavy computations during animation)
   - Review CustomScrollView/Sliver implementations

### Phase 4: Code Consistency Improvements

1. **Widget Extraction**
   - Extract repeated UI patterns into reusable widgets
   - Ensure extracted widgets follow existing naming patterns

2. **State Management**
   - Verify Provider usage is consistent
   - Check for proper disposal of controllers/streams

3. **Error Handling**
   - Standardize try/catch patterns
   - Ensure consistent loading/error state UI

### Phase 5: Verification

After all changes:
1. Run `flutter analyze` - must pass with 0 issues
2. Run `flutter test` if tests exist
3. Create a summary of all changes made
4. List any recommendations that were NOT implemented (too risky)

---

## Execution Instructions

```bash
# Start the audit
cd /home/home-server/Ensemble
git checkout audit/code-quality-review

# After each phase, commit your changes
git add -A && git commit -m "Audit Phase X: [description]"

# Verify no regressions
flutter analyze
```

---

## Expected Deliverables

1. `AUDIT_REPORT.md` - Findings from Phase 1
2. Multiple commits with clear messages for each phase
3. `AUDIT_SUMMARY.md` - Final summary of all changes and remaining recommendations
