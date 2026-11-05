import 'dart:io';
import 'package:flutter/material.dart';

/// Reusable visual primitives for the supplied neon-blue/purple reference.
/// Presentational only: no transport, persistence or permission side effects.
class BlousabVisuals {
  static const Color deep = Color(0xFF050916);
  static const Color panel = Color(0xFF0C142B);
  static const Color electric = Color(0xFF167BFF);
  static const Color cyan = Color(0xFF28C7FF);
  static const Color violet = Color(0xFFB238FF);
  static const Color border = Color(0xFF3858BD);
  static const Gradient neon = LinearGradient(
    begin: Alignment.topRight, end: Alignment.bottomLeft,
    colors: [cyan, electric, violet],
  );
  static BoxDecoration panelDecoration({bool selected = false, double radius = 12}) => BoxDecoration(
    color: selected ? const Color(0xFF11235D) : panel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: selected ? cyan : border, width: selected ? 1.3 : .85),
    boxShadow: [BoxShadow(color: electric.withOpacity(selected ? .29 : .11), blurRadius: selected ? 16 : 7)],
  );
}

class BlousabNeonPanel extends StatelessWidget {
  const BlousabNeonPanel({super.key, required this.child, this.padding = const EdgeInsets.all(10), this.selected = false, this.margin = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.light) {
      return Card(margin: margin, child: Padding(padding: padding, child: child));
    }
    return Container(margin: margin, decoration: BlousabVisuals.panelDecoration(selected: selected), padding: padding, child: child);
  }
}

class BlousabProfileAvatar extends StatelessWidget {
  const BlousabProfileAvatar({super.key, required this.name, this.photoPath, this.radius = 24, this.online = false});
  final String name;
  final String? photoPath;
  final double radius;
  final bool online;
  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    final hasPhoto = path != null && path.isNotEmpty && File(path).existsSync();
    return SizedBox(width: radius * 2 + 8, height: radius * 2 + 8, child: Stack(children: [
      Container(
        padding: const EdgeInsets.all(2.4),
        decoration: const BoxDecoration(gradient: BlousabVisuals.neon, shape: BoxShape.circle),
        child: BlousabKeepColors(child: CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFF172B65),
          backgroundImage: hasPhoto ? FileImage(File(path!)) : null,
          child: hasPhoto ? null : Text(name.isEmpty ? 'ب' : name.substring(0, 1), style: TextStyle(fontSize: radius * .72, fontWeight: FontWeight.bold, color: Colors.white)),
        )),
      ),
      if (online) Positioned(left: 1, bottom: 1, child: Container(width: 12, height: 12,
        decoration: BoxDecoration(color: const Color(0xFF1CE96E), shape: BoxShape.circle, border: Border.all(color: BlousabVisuals.deep, width: 2)))),
    ]));
  }
}

/// Subtle reference-like B motifs behind chats; does not intercept taps.
class BlousabChatWallpaper extends StatelessWidget {
  const BlousabChatWallpaper({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _BlousabMotifPainter()))),
    child,
  ]);
}

class _BlousabMotifPainter extends CustomPainter {
  void _glyph(Canvas canvas, String text, TextStyle style, double x, double y, double angle) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const bStyle = TextStyle(color: Color(0x143975FF), fontSize: 46, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic);
    final heart = TextStyle(color: const Color(0x123975FF), fontSize: 24,
      fontFamily: Icons.favorite_border.fontFamily, package: Icons.favorite_border.fontPackage);
    final plane = TextStyle(color: const Color(0x123975FF), fontSize: 24,
      fontFamily: Icons.send_outlined.fontFamily, package: Icons.send_outlined.fontPackage);
    int n = 0;
    for (double y = 10; y < size.height; y += 88) {
      for (double x = 8; x < size.width; x += 104) {
        final ox = x + (n % 2) * 26;
        _glyph(canvas, 'B', bStyle, ox, y, -.19);
        _glyph(canvas, String.fromCharCode(Icons.favorite_border.codePoint), heart, ox + 52, y + 38, .22);
        _glyph(canvas, String.fromCharCode(Icons.send_outlined.codePoint), plane, ox + 8, y + 54, -.35);
        n++;
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Mockup-matching primitives (neon frame, top bar, bottom navigation, etc.)
// Presentational only.
// ---------------------------------------------------------------------------

/// Phone-edge neon frame + deep background used by every main screen.
class BlousabScreenFrame extends StatelessWidget {
  const BlousabScreenFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!dark) return child;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF040813), Color(0xFF050A1C), Color(0xFF040813)]),
      ),
      child: child,
    );
  }
}

/// Square neon icon button (the "+" box in the mockup header).
class BlousabSquareIconButton extends StatelessWidget {
  const BlousabSquareIconButton({super.key, required this.icon, required this.onTap, this.size = 38, this.color = const Color(0xFF28C7FF), this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color color;
  final String? tooltip;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF06122E),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color, width: 1.8),
          boxShadow: [BoxShadow(color: color.withOpacity(.55), blurRadius: 9)],
        ),
        child: Icon(icon, color: color, size: size * .66),
      ),
    ),
  );
}

/// Bell with red count badge.
class BlousabBell extends StatelessWidget {
  const BlousabBell({super.key, required this.onTap, this.count = 0});
  final VoidCallback? onTap;
  final int count;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: SizedBox(width: 40, height: 40, child: Stack(clipBehavior: Clip.none, children: [
      const Center(child: Icon(Icons.notifications_rounded, color: Colors.white, size: 30)),
      if (count > 0) Positioned(top: 0, right: 3, child: Container(
        constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: const Color(0xFFFF2D3F), shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x88FF2D3F), blurRadius: 6)]),
        alignment: Alignment.center,
        child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      )),
    ])),
  );
}

/// Glowing "بلوساب" title.
class BlousabGlowTitle extends StatelessWidget {
  const BlousabGlowTitle(this.text, {super.key, this.size = 33});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(
    color: Colors.white, fontSize: size, fontWeight: FontWeight.w800, height: 1.1,
    shadows: const [Shadow(color: Color(0xFF5B8CFF), blurRadius: 14), Shadow(color: Color(0xFF2A62FF), blurRadius: 26)],
  ));
}

/// Standard header row of the main tabs: [leading] ... title ... [trailing].
/// In RTL, `start` is the right side.
class BlousabTopBar extends StatelessWidget {
  const BlousabTopBar({super.key, required this.start, required this.end, this.title = 'بلوساب', this.titleWidget});
  final List<Widget> start;
  final List<Widget> end;
  final String title;
  final Widget? titleWidget;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        ...start,
        Expanded(child: Center(child: titleWidget ?? BlousabGlowTitle(title))),
        ...end,
      ]),
    ),
  );
}

/// Pill-shaped action with coloured neon border (chat-list actions).
class BlousabNeonPill extends StatelessWidget {
  const BlousabNeonPill({super.key, required this.label, required this.icon, required this.color, required this.onTap, this.height = 46, this.fontSize = 11.5});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double height;
  final double fontSize;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        gradient: LinearGradient(colors: [color.withOpacity(.10), color.withOpacity(.26)]),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color, width: 1.5),
        boxShadow: [BoxShadow(color: color.withOpacity(.45), blurRadius: 10)],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color == const Color(0xFFFF9A1F) ? const Color(0xFF3EA0FF) : Colors.white, size: 24),
        const SizedBox(width: 6),
        Flexible(child: Text(label, maxLines: 2, textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600, height: 1.15))),
      ]),
    ),
  );
}

/// Bottom navigation matching the mockup. Visual order (left -> right):
/// chats, posts, stories, profile. Indexes: 0 chats, 1 posts, 2 stories, 3 profile.
class BlousabBottomNav extends StatelessWidget {
  const BlousabBottomNav({super.key, required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const _items = <List<Object>>[
    [0, Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 'المحادثات'],
    [1, Icons.grid_view_rounded, Icons.grid_view_rounded, 'المنشورات'],
    [2, Icons.play_circle_outline_rounded, Icons.play_circle_outline_rounded, 'القصص'],
    [3, Icons.person_rounded, Icons.person_rounded, 'الملف الشخصي'],
  ];

  @override
  Widget build(BuildContext context) {
    // The app is RTL: the first child sits on the right, so reverse the list
    // to put المحادثات on the left exactly like the mockup.
    final children = _items.reversed.map((it) {
      final i = it[0] as int;
      final selected = i == index;
      return Expanded(child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
          decoration: selected ? BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF081844),
            border: Border.all(color: const Color(0xFF3F7BFF), width: 1.4),
            boxShadow: const [BoxShadow(color: Color(0x663F7BFF), blurRadius: 12)],
          ) : null,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(selected ? it[1] as IconData : it[2] as IconData, size: 29,
              color: selected ? const Color(0xFF3FA2FF) : const Color(0xFF8FB2FF)),
            const SizedBox(height: 2),
            Text(it[3] as String, maxLines: 1, style: TextStyle(
              fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? const Color(0xFF38D6FF) : Colors.white,
              shadows: selected ? const [Shadow(color: Color(0xFF2A8BFF), blurRadius: 8)] : null)),
            const SizedBox(height: 2),
            AnimatedContainer(duration: const Duration(milliseconds: 180), height: 3, width: selected ? 38 : 0,
              decoration: BoxDecoration(color: const Color(0xFF38D6FF), borderRadius: BorderRadius.circular(3),
                boxShadow: const [BoxShadow(color: Color(0xFF38D6FF), blurRadius: 6)])),
          ]),
        ),
      ));
    }).toList();
    return Container(
      height: 70,
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF050B1E),
        border: Border.all(color: const Color(0xFF3B63FF), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x773B63FF), blurRadius: 14), BoxShadow(color: Color(0x44B338FF), blurRadius: 10)],
      ),
      child: Row(children: children),
    );
  }
}

/// Neon-gradient bordered round avatar used in chat lists, headers & stories.
class BlousabRingAvatar extends StatelessWidget {
  const BlousabRingAvatar({super.key, required this.name, this.photoPath, this.size = 56, this.online = false, this.ring = 3.0, this.child});
  final String name;
  final String? photoPath;
  final double size;
  final bool online;
  final double ring;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    final hasPhoto = path != null && path.isNotEmpty && File(path).existsSync();
    final inner = size - ring * 2;
    return SizedBox(width: size, height: size, child: Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size, height: size, padding: EdgeInsets.all(ring),
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF28C7FF), Color(0xFF2D6BFF), Color(0xFFB238FF)]),
          boxShadow: [BoxShadow(color: Color(0x662D6BFF), blurRadius: 10)]),
        child: ClipOval(child: BlousabKeepColors(child: SizedBox(width: inner, height: inner, child: child ?? (hasPhoto
          ? Image.file(File(path!), fit: BoxFit.cover)
          : Container(color: const Color(0xFF14235A), alignment: Alignment.center,
              child: Text(name.isEmpty ? 'ب' : name.substring(0, 1),
                style: TextStyle(color: Colors.white, fontSize: inner * .42, fontWeight: FontWeight.w800))))))),
      ),
      if (online) Positioned(right: 0, bottom: 1, child: Container(width: size * .24, height: size * .24,
        decoration: BoxDecoration(color: const Color(0xFF22E56A), shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF050916), width: 2),
          boxShadow: const [BoxShadow(color: Color(0x8822E56A), blurRadius: 6)]))),
    ]));
  }
}

class BlousabVerifiedBadge extends StatelessWidget {
  const BlousabVerifiedBadge({super.key, this.size = 20});
  final double size;
  // علامة التوثيق معطّلة حاليًا بناءً على الطلب. أعد الأيقونة هنا عند تفعيل التوثيق.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Neon card used for chat rows / posts / list panels.
BoxDecoration blousabCardDecoration({double radius = 16, Color border = const Color(0xFF2B48A8), bool glow = true}) => BoxDecoration(
  borderRadius: BorderRadius.circular(radius),
  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [Color(0xFF0A1330), Color(0xFF070E26)]),
  border: Border.all(color: border, width: 1.2),
  boxShadow: glow ? const [BoxShadow(color: Color(0x332D6BFF), blurRadius: 9)] : null,
);

/// Soft neon swirl drawn behind the profile header.
class BlousabWaveBackground extends StatelessWidget {
  const BlousabWaveBackground({super.key, this.height = 300});
  final double height;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _WavePainter())),
  );
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final shader = const LinearGradient(colors: [Color(0xFF28C7FF), Color(0xFF2D6BFF), Color(0xFFB238FF)])
        .createShader(Rect.fromLTWH(0, 0, w, h));
    for (int i = 0; i < 7; i++) {
      final path = Path()
        ..moveTo(-10, h * (.40 + i * .012))
        ..cubicTo(w * .22, h * (.12 + i * .02), w * .45, h * (.62 - i * .015), w * .72, h * (.30 + i * .02))
        ..cubicTo(w * .86, h * (.18 + i * .01), w * .95, h * (.22 + i * .02), w + 10, h * (.10 + i * .015));
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == 3 ? 2.6 : 1.2
        ..shader = shader
        ..color = Colors.white.withOpacity(.5 - i * .04)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, i == 3 ? 3.5 : 1.5));
    }
    canvas.drawCircle(Offset(w * .5, h * .38), w * .42, Paint()
      ..shader = const RadialGradient(colors: [Color(0x552D6BFF), Color(0x00000000)])
          .createShader(Rect.fromCircle(center: Offset(w * .5, h * .38), radius: w * .42)));
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


// ---------------------------------------------------------------------------
// الوضع النهاري / الليلي
// ---------------------------------------------------------------------------
// كل ألوان الواجهات مصممة للوضع الداكن. في الوضع النهاري يُطبَّق مرشح
// (قلب السطوع + تدوير الصبغة 180°) على التطبيق كله فتصبح الخلفيات بيضاء
// والنصوص داكنة وتبقى الألوان الزرقاء/البنفسجية قريبة من هوية بلوساب.
// الصور والفيديو تُغلَّف بـ BlousabKeepColors لتعود لألوانها الأصلية.
const ColorFilter blousabLightModeFilter = ColorFilter.matrix(<double>[
   0.574, -1.430, -0.144, 0, 255,
  -0.426, -0.430, -0.144, 0, 255,
  -0.426, -1.430,  0.856, 0, 255,
   0,      0,      0,     1,   0,
]);

/// Set by the app root. true = night (dark) mode.
final ValueNotifier<bool> blousabNightMode = ValueNotifier<bool>(true);

/// Re-applies the light-mode filter so photos/videos keep their real colours.
class BlousabKeepColors extends StatelessWidget {
  const BlousabKeepColors({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: blousabNightMode,
    builder: (context, night, _) => night
        ? child
        : ColorFiltered(colorFilter: blousabLightModeFilter, child: child),
  );
}

// ---------------------------------------------------------------------------
// أيقونة "مستخدم مجهول" للبحث عن المستخدمين
// ---------------------------------------------------------------------------
/// صورة مستخدم مجهول (رأس وكتفان) داخل حلقة نيون، وعليها شرطة مائلة.
class BlousabAnonymousUserIcon extends StatelessWidget {
  const BlousabAnonymousUserIcon({super.key, this.size = 72, this.color = BlousabVisuals.cyan});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(painter: _AnonymousUserPainter(color)),
  );
}

class _AnonymousUserPainter extends CustomPainter {
  _AnonymousUserPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;
    // خلفية دائرية + حلقة نيون
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0A1330));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .045
      ..shader = const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [BlousabVisuals.cyan, BlousabVisuals.electric, BlousabVisuals.violet],
      ).createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r - size.width * .03)));
    final body = Paint()..color = color.withOpacity(.85);
    // الرأس
    canvas.drawCircle(Offset(c.dx, c.dy - r * .22), r * .27, body);
    // الكتفان
    final shoulders = Path()
      ..moveTo(c.dx - r * .62, c.dy + r * .95)
      ..quadraticBezierTo(c.dx - r * .62, c.dy + r * .22, c.dx, c.dy + r * .22)
      ..quadraticBezierTo(c.dx + r * .62, c.dy + r * .22, c.dx + r * .62, c.dy + r * .95)
      ..close();
    canvas.drawPath(shoulders, body);
    canvas.restore();
    // الشرطة المائلة (مجهول)
    final a = Offset(c.dx - r * .62, c.dy - r * .62);
    final b = Offset(c.dx + r * .62, c.dy + r * .62);
    canvas.drawLine(a, b, Paint()
      ..color = const Color(0xFF0A1330)
      ..strokeWidth = size.width * .12
      ..strokeCap = StrokeCap.round);
    canvas.drawLine(a, b, Paint()
      ..color = const Color(0xFFFF4D6D)
      ..strokeWidth = size.width * .065
      ..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(covariant _AnonymousUserPainter old) => old.color != color;
}
