// Small banner shown whenever the screen is displaying bundled SAMPLE
// prices (backend unreachable). Sample prices must never be presented
// as live prices. Shown in the current language.

import 'package:flutter/material.dart';

import '../l10n/strings.dart';

class SampleBanner extends StatelessWidget {
  const SampleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF92400E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(context, 'sampleBanner'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }
}
