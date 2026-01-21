import 'package:flutter/material.dart';

/// Display mode for the scrollbar popup indicator
enum ScrollbarDisplayMode {
  /// Show first letter of item name (A, B, C, #)
  letter,
  /// Show year (2024, 2023, etc.)
  year,
  /// Show count number
  count,
  /// Hide the popup (just show scrollbar thumb)
  none,
}

/// A scrollbar that shows a contextual popup when dragging, for fast navigation
/// through sorted lists.
///
/// Scrolls PROPORTIONALLY (like a normal scrollbar) and shows contextual info
/// about the current position via a popup indicator. The popup content adapts
/// based on the display mode (letters for alphabetical, years for date sorts,
/// counts for play count sorts).
class LetterScrollbar extends StatefulWidget {
  /// The scrollable child widget (ListView, GridView, etc.)
  final Widget child;

  /// The scroll controller for the child
  final ScrollController controller;

  /// List of strings to extract letters from (should match visual sort order).
  /// Each item's first character is used to determine the letter shown in the popup.
  final List<String> items;

  /// Display mode for the popup indicator
  final ScrollbarDisplayMode displayMode;

  /// Custom display labels for each item (optional).
  /// When provided, these are shown in the popup instead of extracting letters.
  /// Length must match [items] if provided.
  final List<String>? displayLabels;

  /// Callback when user taps/drags to a specific index.
  final void Function(int index)? onScrollToIndex;

  /// Callback when drag state changes (for disabling scroll-to-hide)
  final void Function(bool isDragging)? onDragStateChanged;

  /// Fixed item height for lists. Enables precise scroll calculation.
  final double? itemExtent;

  /// Number of columns for grid layouts.
  final int? crossAxisCount;

  /// Aspect ratio of grid children (width / height).
  final double? childAspectRatio;

  /// Spacing between grid rows (mainAxisSpacing)
  final double? mainAxisSpacing;

  /// Horizontal padding of the scrollable area
  final double? horizontalPadding;

  /// Bottom padding to prevent scrollbar from going behind bottom nav/mini player
  final double bottomPadding;

  const LetterScrollbar({
    super.key,
    required this.child,
    required this.controller,
    required this.items,
    this.displayMode = ScrollbarDisplayMode.letter,
    this.displayLabels,
    this.onScrollToIndex,
    this.onDragStateChanged,
    this.itemExtent,
    this.crossAxisCount,
    this.childAspectRatio,
    this.mainAxisSpacing,
    this.horizontalPadding,
    this.bottomPadding = 0,
  });

  @override
  State<LetterScrollbar> createState() => _LetterScrollbarState();
}

class _LetterScrollbarState extends State<LetterScrollbar> {
  bool _isDragging = false;
  String _currentLetter = '';
  double _dragPosition = 0;
  double _scrollFraction = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScrollChanged);
    super.dispose();
  }

  void _onScrollChanged() {
    if (!_isDragging && widget.controller.hasClients) {
      final position = widget.controller.position;
      if (position.maxScrollExtent > 0) {
        final newFraction = (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
        if ((newFraction - _scrollFraction).abs() > 0.01) {
          setState(() {
            _scrollFraction = newFraction;
            _currentLetter = _getLabelAtFraction(newFraction);
          });
        }
      }
    }
  }

  /// Normalizes a character to a letter for the scrollbar.
  String _normalizeToLetter(String char) {
    if (char.isEmpty) return '';
    final upper = char[0].toUpperCase();
    if (upper.codeUnitAt(0) >= 65 && upper.codeUnitAt(0) <= 90) {
      return upper;
    }
    return '#';
  }

  /// Get the display label at a given scroll fraction (0.0 to 1.0)
  String _getLabelAtFraction(double fraction) {
    if (widget.items.isEmpty) return '';

    final index = (fraction * (widget.items.length - 1)).round().clamp(0, widget.items.length - 1);

    // Use custom display labels if provided
    if (widget.displayLabels != null && index < widget.displayLabels!.length) {
      return widget.displayLabels![index];
    }

    // Otherwise extract from items based on display mode
    if (index < widget.items.length) {
      final item = widget.items[index];
      if (item.isNotEmpty) {
        switch (widget.displayMode) {
          case ScrollbarDisplayMode.letter:
            return _normalizeToLetter(item[0]);
          case ScrollbarDisplayMode.year:
          case ScrollbarDisplayMode.count:
            // For year/count modes, the item itself should be the display value
            return item;
          case ScrollbarDisplayMode.none:
            // No popup shown, return empty
            return '';
        }
      }
    }
    return '';
  }

  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragPosition = details.localPosition.dy;
    });
    widget.onDragStateChanged?.call(true);
    _scrollToPosition(details.localPosition.dy);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragPosition = details.localPosition.dy;
    });
    _scrollToPosition(details.localPosition.dy);
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });
    widget.onDragStateChanged?.call(false);
  }

  /// Scroll proportionally based on drag position
  void _scrollToPosition(double position) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !widget.controller.hasClients) return;

    // Account for bottom padding in the effective track height
    final totalHeight = renderBox.size.height;
    final effectiveHeight = totalHeight - widget.bottomPadding;
    if (effectiveHeight <= 0) return;

    // Calculate scroll fraction from position (clamped to effective area)
    final clampedPosition = position.clamp(0.0, effectiveHeight);
    final fraction = clampedPosition / effectiveHeight;

    // Get letter for display
    final letter = _getLabelAtFraction(fraction);

    // Scroll proportionally
    final maxScroll = widget.controller.position.maxScrollExtent;
    final targetScroll = (fraction * maxScroll).clamp(0.0, maxScroll);

    setState(() {
      _scrollFraction = fraction;
      if (letter.isNotEmpty) {
        _currentLetter = letter;
      }
    });

    widget.controller.jumpTo(targetScroll);
  }

  /// Build the popup bubble with appropriate size and styling based on display mode
  Widget _buildPopupBubble(ColorScheme colorScheme) {
    // Determine size and font based on content length and display mode
    final double width;
    final double height;
    final double fontSize;

    switch (widget.displayMode) {
      case ScrollbarDisplayMode.letter:
      case ScrollbarDisplayMode.none: // Fallback (none won't actually reach here)
        width = 56;
        height = 56;
        fontSize = 28;
        break;
      case ScrollbarDisplayMode.year:
        width = 72;
        height = 48;
        fontSize = 22;
        break;
      case ScrollbarDisplayMode.count:
        // Dynamic width based on count length
        final labelLength = _currentLetter.length;
        width = labelLength <= 2 ? 56 : (labelLength <= 4 ? 72 : 88);
        height = 48;
        fontSize = labelLength <= 3 ? 22 : 18;
        break;
    }

    return Material(
      elevation: 4,
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        child: Text(
          _currentLetter,
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // The scrollable content
        widget.child,

        // The draggable scrollbar area (right edge)
        Positioned(
          right: 0,
          top: 0,
          bottom: widget.bottomPadding,
          width: 32,
          child: GestureDetector(
            onVerticalDragStart: _handleDragStart,
            onVerticalDragUpdate: _handleDragUpdate,
            onVerticalDragEnd: _handleDragEnd,
            onTapDown: (details) {
              _handleDragStart(DragStartDetails(
                localPosition: details.localPosition,
                globalPosition: details.globalPosition,
              ));
            },
            onTapUp: (_) {
              setState(() {
                _isDragging = false;
              });
              widget.onDragStateChanged?.call(false);
            },
            behavior: HitTestBehavior.translucent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackHeight = constraints.maxHeight;
                final thumbHeight = _isDragging ? 60.0 : 40.0;
                final availableTrack = trackHeight - thumbHeight;
                final thumbTop = (availableTrack * _scrollFraction).clamp(0.0, availableTrack);

                return Stack(
                  children: [
                    // Thumb that tracks scroll position
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 50),
                      curve: Curves.linear,
                      top: thumbTop,
                      right: 4,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: _isDragging ? 6 : 4,
                        height: thumbHeight,
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? colorScheme.primary
                              : colorScheme.onSurface.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // The popup bubble (letter, year, or count) - hidden when displayMode is none
        if (_isDragging && _currentLetter.isNotEmpty && widget.displayMode != ScrollbarDisplayMode.none)
          Positioned(
            right: 48,
            top: (_dragPosition - 28).clamp(
              0.0,
              (context.findRenderObject() as RenderBox?)?.size.height ?? 500 - 56 - widget.bottomPadding,
            ),
            child: _buildPopupBubble(colorScheme),
          ),
      ],
    );
  }
}
