import 'package:flutter/material.dart';

import '../theme/spartan_theme.dart';

class SpartanBrand extends StatelessWidget {
  const SpartanBrand({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/images/spartan_brand.png',
        width: 36,
        height: 36,
        semanticLabel: 'SPARTAN',
      ),
      if (!compact) ...[
        const SizedBox(width: 10),
        const Text(
          'SPARTAN',
          style: TextStyle(
            color: SpartanPalette.gold,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
      ],
    ],
  );
}
