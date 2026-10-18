import 'dart:convert';
import 'dart:io';

import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/template.dart';

ExerciseLibrary loadLibrary() => ExerciseLibrary.fromJson(
  jsonDecode(File('assets/library/exercises.json').readAsStringSync())
      as Map<String, dynamic>,
);

TemplateCatalog loadCatalog() => TemplateCatalog.fromJson(
  jsonDecode(File('assets/library/templates.json').readAsStringSync())
      as Map<String, dynamic>,
);
