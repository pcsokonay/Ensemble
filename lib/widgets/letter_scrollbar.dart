import 'package:flutter/material.dart';

/// A scrollbar that shows a letter popup when dragging, for fast navigation
/// through alphabetically sorted lists.
///
/// Scrolls PROPORTIONALLY (like a normal scrollbar) and shows which letter
/// section you're currently in via a popup indicator.
class LetterScrollbar extends StatefulWidget {
  /// The scrollable child widget (ListView, GridView, etc.)
  final Widget child;

  /// The scroll controller for the child
  final ScrollController controller;

  /// List of strings to extract letters from (should match visual sort order).
  /// Each item's first character is used to determine the letter shown in the popup.
  final List<String> items;

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
            _currentLetter = _getLetterAtFraction(newFraction);
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

  /// Get the letter at a given scroll fraction (0.0 to 1.0)
  String _getLetterAtFraction(double fraction) {
    if (widget.items.isEmpty) return '';

    final index = (fraction * (widget.items.length - 1)).round().clamp(0, widget.items.length - 1);
    if (index < widget.items.length) {
      final item = widget.items[index];
      if (item.isNotEmpty) {
        return _normalizeToLetter(item[0]);
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
    final letter = _getLetterAtFraction(fraction);

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

        // The letter popup bubble
        if (_isDragging && _currentLetter.isNotEmpty)
          Positioned(
            right: 48,
            top: (_dragPosition - 28).clamp(
              0.0,
              (context.findRenderObject() as RenderBox?)?.size.height ?? 500 - 56 - widget.bottomPadding,
            ),
            child: Material(
              elevation: 4,
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                child: Text(
                  _currentLetter,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
