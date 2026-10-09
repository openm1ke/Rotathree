import 'package:flutter/material.dart';

import '../style.dart';
import 'strings.dart';

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.value, required this.onChanged});
  final LanguageChoice value;
  final ValueChanged<LanguageChoice> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final choice in LanguageChoice.values) ...[
        if (choice != LanguageChoice.auto) const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            button: true,
            selected: choice == value,
            child: Material(
              color: choice == value ? Palette.accent.withValues(alpha: 0.16) : Palette.panel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: choice == value ? Palette.accent : Palette.line),
              ),
              child: InkWell(
                key: ValueKey('language-${choice.name}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(choice),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  child: Column(
                    children: [
                      ExcludeSemantics(
                        child: choice == LanguageChoice.auto
                            ? const Icon(Icons.language, size: 24, color: Palette.accent)
                            : CustomPaint(size: const Size(32, 24), painter: _FlagPainter(choice)),
                      ),
                      const SizedBox(height: 6),
                      LText(
                        switch (choice) {
                          LanguageChoice.auto => 'Авто',
                          LanguageChoice.ru => 'Русский',
                          LanguageChoice.en => 'English',
                        },
                        translate: choice == LanguageChoice.auto,
                        style: Type.body(13, weight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class _FlagPainter extends CustomPainter {
  const _FlagPainter(this.language);
  final LanguageChoice language;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)));
    final paint = Paint();
    if (language == LanguageChoice.ru) {
      for (var i = 0; i < 3; i++) {
        paint.color = [Colors.white, const Color(0xFF2256B4), const Color(0xFFD83947)][i];
        canvas.drawRect(Rect.fromLTWH(0, i * size.height / 3, size.width, size.height / 3), paint);
      }
    } else {
      canvas.drawRect(Offset.zero & size, paint..color = const Color(0xFF173674));
      for (final color in [Colors.white, const Color(0xFFD83947)]) {
        paint
          ..color = color
          ..strokeWidth = color == Colors.white ? 6 : 2;
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
      }
      for (final color in [Colors.white, const Color(0xFFD83947)]) {
        paint
          ..color = color
          ..strokeWidth = color == Colors.white ? 9 : 5;
        canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
        canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FlagPainter old) => old.language != language;
}
