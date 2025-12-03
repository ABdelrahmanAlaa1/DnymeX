import 'dart:async';

import 'package:flutter/material.dart';

class HoldToCancelDetector extends StatefulWidget {
  const HoldToCancelDetector({
    super.key,
    required this.child,
    required this.onConfirmed,
    this.duration = const Duration(seconds: 2),
    this.tooltip,
    this.overlayRadius,
    this.enabled = true,
    this.progressColor,
  });

  final Widget child;
  final Future<void> Function() onConfirmed;
  final Duration duration;
  final String? tooltip;
  final BorderRadius? overlayRadius;
  final bool enabled;
  final Color? progressColor;

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

  void _startHold() {
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => _startHold() : null,
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
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
