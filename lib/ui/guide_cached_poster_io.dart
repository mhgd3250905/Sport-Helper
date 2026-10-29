import 'dart:io';

import 'package:flutter/material.dart';

Widget guideCachedPoster(
  String path, {
  required int cacheWidth,
  ImageErrorWidgetBuilder? errorBuilder,
}) => Image.file(
  File(path),
  fit: BoxFit.contain,
  cacheWidth: cacheWidth,
  errorBuilder: errorBuilder,
);
