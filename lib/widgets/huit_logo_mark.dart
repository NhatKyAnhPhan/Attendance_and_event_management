import 'package:flutter/material.dart';

class HuitLogoMark extends StatelessWidget {
  const HuitLogoMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/LogoHUIT.jpg',
      fit: BoxFit.cover,
      semanticLabel: 'Logo HUIT',
    );
  }
}
