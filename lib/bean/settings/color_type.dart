import 'package:flutter/material.dart';

typedef ColorTheme = ({Color color, String label});

const List<ColorTheme> colorThemeTypes = [
  (color: Color(0xFF00D4AA), label: '青色（默认）'),
  (color: Colors.green, label: '绿色'),
  (color: Colors.teal, label: '青绿色'),
  (color: Colors.blue, label: '蓝色'),
  (color: Colors.indigo, label: '靛蓝色'),
  (color: Color(0xff6750a4), label: '紫罗兰色'),
  (color: Colors.pink, label: '粉红色'),
  (color: Colors.yellow, label: '黄色'),
  (color: Colors.orange, label: '橙色'),
  (color: Colors.deepOrange, label: '深橙色'),
];
