import 'package:flutter/material.dart';

import 'theme.dart';

class TourStep {
  const TourStep({this.target, required this.title, required this.body});

  /// Widget to spotlight. Null = centered card with no spotlight.
  final GlobalKey? target;
  final String title;
  final String body;
}

/// Coach-mark style first-launch tour: dims the screen, cuts a spotlight
/// around the target widget and shows an explanation card next to it.
class TourOverlay extends StatefulWidget {
  const TourOverlay({super.key, required this.steps, required this.onFinish});

  final List<TourStep> steps;
  final VoidCallback onFinish;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  int _i = 0;
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final key = widget.steps[_i].target;
    Rect? r;
    final ctx = key?.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      final me = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && me != null) {
        final topLeft = box.localToGlobal(Offset.zero, ancestor: me);
        r = (topLeft & box.size).inflate(4);
      }
    }
    setState(() => _rect = r);
  }

  void _go(int delta) {
    final next = _i + delta;
    if (next >= widget.steps.length) {
      widget.onFinish();
      return;
    }
    if (next < 0) return;
    setState(() => _i = next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final nb = context.nb;
    final size = MediaQuery.sizeOf(context);
    final rect = step.target == null ? null : _rect;
    final last = _i == widget.steps.length - 1;

    // Place the card below the spotlight if there's room, else above.
    const cardMargin = 16.0;
    double? top, bottom;
    if (rect == null) {
      top = null;
    } else if (rect.bottom + 220 < size.height) {
      top = rect.bottom + 14;
    } else {
      bottom = size.height - rect.top + 14;
    }

    final card = Material(
      color: nb.paper,
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: nb.columnRule.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              step.title,
              style: TextStyle(
                fontFamily: kTitleFont,
                fontSize: 32,
                height: 1.0,
                fontWeight: FontWeight.w700,
                color: nb.ink,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                step.body,
                style: TextStyle(fontSize: 19, height: 1.3, color: nb.ink),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${_i + 1} / ${widget.steps.length}',
                  style: TextStyle(color: nb.fadedInk, fontSize: 17),
                ),
                const Spacer(),
                if (!last)
                  TextButton(
                    onPressed: widget.onFinish,
                    child: const Text('Skip'),
                  ),
                if (_i > 0)
                  TextButton(
                    onPressed: () => _go(-1),
                    child: const Text('Back'),
                  ),
                FilledButton(
                  onPressed: () => _go(1),
                  child: Text(last ? 'Start writing' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // swallow taps on the app underneath
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _SpotlightPainter(rect)),
            ),
            if (rect != null)
              Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ),
            if (rect == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(cardMargin),
                  child: card,
                ),
              )
            else
              Positioned(
                left: cardMargin,
                right: cardMargin,
                top: top,
                bottom: bottom,
                child: card,
              ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Path()..addRect(Offset.zero & size);
    final path = hole == null
        ? bg
        : Path.combine(
            PathOperation.difference,
            bg,
            Path()..addRRect(
              RRect.fromRectAndRadius(hole!, const Radius.circular(12)),
            ),
          );
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}
