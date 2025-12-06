import 'dart:async';

import 'package:flutter/material.dart';

class HoldToCancelDetector extends StatefulWidget {
  const HoldToCancelDetector({
    super.key,
    required this.child,
    required this.onConfirmed,
    this.duration = const Duration(milliseconds: 1200),
    this.tooltip,
    this.overlayRadius,
    this.enabled = true,
    this.progressColor,
    this.movementTolerance = 35,
  });

  final Widget child;
  final Future<void> Function() onConfirmed;
  final Duration duration;
  final String? tooltip;
  final BorderRadius? overlayRadius;
  final bool enabled;
  final Color? progressColor;
  final double movementTolerance;

  @override
  State<HoldToCancelDetector> createState() => _HoldToCancelDetectorState();
}

class _HoldToCancelDetectorState extends State<HoldToCancelDetector> {
  Timer? _timer;
  DateTime? _startTime;
  double _progress = 0;
  bool _isHolding = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startHold(PointerDownEvent event) {
    if (!widget.enabled) return;
    _timer?.cancel();
    _startTime = DateTime.now();
    setState(() {
      _isHolding = true;
      _progress = 0;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 32), (timer) {
      final start = _startTime;
      if (start == null) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(start);
      final fraction = (elapsed.inMilliseconds / widget.duration.inMilliseconds)
          .clamp(0.0, 1.0);
      setState(() => _progress = fraction);
      if (fraction >= 1) {
        timer.cancel();
        _finishHold();
      }
    });
  }

  Future<void> _finishHold() async {
    _startTime = null;
    setState(() {
      _isHolding = false;
      _progress = 0;
    });
    await widget.onConfirmed();
  }

  void _cancelHold() {
    _timer?.cancel();
    _timer = null;
    _startTime = null;
    if (_isHolding) {
      setState(() {
        _isHolding = false;
        _progress = 0;
      });
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.enabled || !_isHolding) return;
    if (!_isWithinTolerance(event.position)) {
      _cancelHold();
    }
  }

  bool _isWithinTolerance(Offset globalPosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return true;
    }
    final localPosition = renderBox.globalToLocal(globalPosition);
    final tolerance = widget.movementTolerance;
    final expandedRect = Rect.fromLTWH(
      -tolerance,
      -tolerance,
      renderBox.size.width + (tolerance * 2),
      renderBox.size.height + (tolerance * 2),
    );
    return expandedRect.contains(localPosition);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.tooltip == null
        ? widget.child
        : Tooltip(message: widget.tooltip!, child: widget.child);

    final overlayRadius = widget.overlayRadius ?? BorderRadius.circular(9999);
    final overlayColor = Theme.of(context)
        .colorScheme
        .error
        .withOpacity(widget.enabled ? 0.15 : 0);
    final indicatorColor =
        widget.progressColor ?? Theme.of(context).colorScheme.error;

    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: widget.enabled ? _startHold : null,
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) => _cancelHold(),
      onPointerCancel: (_) => _cancelHold(),
      child: Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.center,
        children: [
          child,
          if (_isHolding)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: overlayRadius,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: overlayColor),
                  ),
                ),
              ),
            ),
          if (_isHolding)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: _progress,
                valueColor: AlwaysStoppedAnimation(indicatorColor),
              ),
            ),
        ],
      ),
    );
  }
}
