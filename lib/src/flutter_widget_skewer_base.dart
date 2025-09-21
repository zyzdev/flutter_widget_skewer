// lib/builder.dart
  import 'dart:convert';
  import 'dart:io';
  import 'dart:core';
  import 'dart:core' as core;

  import 'package:analyzer/dart/analysis/analysis_context.dart';
  import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
  import 'package:analyzer/dart/analysis/results.dart';
  import 'package:analyzer/dart/ast/ast.dart';
  import 'package:analyzer/dart/element/element.dart';
  import 'package:analyzer/dart/element/type.dart';
  import 'package:build/build.dart';
  import 'package:collection/collection.dart';
  import 'package:path/path.dart' as p;

  /// builder factory
  Builder flutterWidgetSkewerBuilder(BuilderOptions options) =>
      FlutterWidgetSkewerBuilder();

  class FlutterWidgetSkewerBuilder implements Builder {
    /// =================== For Debug ===================
    /// Class name to trace
    String? _focusClass;

    bool get _debugPrint =>
        _focusClass != null && (_focusClass?.isNotEmpty ?? false);

    void print(Object? msg, [String? method]) {
      if (_debugPrint)
        core.print('${method != null ? '[$method]: ' : ''}${msg?.toString()}');
    }

    /// =================== For Debug ===================

    /// Required Widget parameters used to determine whether a Widget is functional
    static const List<String> _caredWidgetParamName = [
      'child',
      'children',
      'slivers'
    ];

    @override
    final buildExtensions = const {
      r'$lib$': ['gen/flutter_widget_skewer.g.dart'],
    };

    /// all [ClassDeclaration] in Flutter SDK
    List<ClassDeclaration> _allDecl = [];

    /// Widgets to ignore (limitations)
    List<String> _ignoreWidget = [
      'CupertinoTextSelectionToolbar',
      'TextSelectionToolbar'
    ];

    /// Specialized import
    List<String> _specialImport = [
      '\'package:flutter/material.dart\' as m show RefreshCallback;',
    ];

    /// General imports
    Set<String> get _imports => <String>{
      '\'package:flutter/material.dart\';',
      '\'package:flutter/cupertino.dart\';',
      '\'package:flutter/gestures.dart\';',
      '\'package:flutter/services.dart\';',
      '\'package:flutter/rendering.dart\';',
      '\'package:flutter/foundation.dart\';',
      '\'dart:ui\';',
      '\'dart:ui\' as ui;',
      ..._specialImport
    };

    late AnalysisContextCollection _collection;
    late AnalysisContext _context;

    @override
    Future<void> build(BuildStep buildStep) async {
      final sdkPath = await getFlutterSdkPath(projectRoot: p.current);
      if (sdkPath == null) {
        log.severe('Flutter SDK path not found!');
        return;
      }
      log.info('Flutter SDK path: $sdkPath');

      final List<ClassDeclaration> widgetDecles = [];

      _collection = AnalysisContextCollection(includedPaths: [sdkPath]);
      _context = _collection.contextFor(sdkPath);

      for (final String filePath in _context.contextRoot.analyzedFiles()) {
        // Filter out non-Dart files
        if (!filePath.endsWith('.dart')) continue;
        // Filter out .dart files whose filename starts with '_'
        if (filePath.split('/').last.startsWith('_')) continue;

        // Analyze *.dart
        AnalysisContext context = _collection.contextFor(filePath);
        ResolvedUnitResult result = await context.currentSession
            .getResolvedUnit(filePath) as ResolvedUnitResult;
        for (final decl in result.unit.declarations) {
          if (decl is! ClassDeclaration) continue;
          // Collect all class declarations from Flutter SDK files
          _allDecl.add(decl);
        }
      }

      // Find target Widget classes to analyze
      for (var decl in _allDecl) {
        ClassElement cls = decl.declaredElement!;
        // for debug to trace special class by name
        if (_focusClass != null) if (cls.name != _focusClass) continue;
        if (await _isWidgetClassDeclaration(decl)) widgetDecles.add(decl);
      }

      log.info('Found ${widgetDecles.length} 個 ClassDeclaration classes');

      final singleChildFns = <String>[];
      final multiChildFns = <String>[];

      ConstructorElement? _pickConstructor(ClassElement cls) {
        return cls.constructors.firstWhereOrNull(
              (c) => c.name == '' && !c.isPrivate,
        ) ??
            cls.constructors.firstWhereOrNull((c) => !c.isPrivate) ??
            (cls.constructors.isNotEmpty ? cls.constructors.first : null);
      }

      String _lowerFirst(String s) {
        if (s.isEmpty) return s;
        return s[0].toLowerCase() + s.substring(1);
      }

      for (final decl in widgetDecles) {
        ClassElement cls = decl.declaredElement!;

        // for debug to trace special class by name
        if (_focusClass != null) if (cls.name != _focusClass) continue;

        final ctor = _pickConstructor(cls);
        if (ctor == null) continue;

        for (final member in decl.members) {
          if (member is! ConstructorDeclaration) continue;
          String constructorName = member.declaredElement!.displayName;
          // Ignored list
          if (_ignoreWidget.contains(constructorName)) continue;
          // Private constructor
          if (constructorName.contains('_')) continue;

          // Skip this class
          bool pass = false;

          // Class has child or children
          bool? isSingleChild;
          final params = <String>[];
          final namedParams = <String>[];
          final optionalParams = <String>[];
          final args = <String>[];
          final namedArgs = <String>[];
          final optionalArgs = <String>[];

          print('[$constructorName] constructor →');
          print('path:${decl.declaredElement?.source.fullName}');
          for (final param in member.parameters.parameters) {
            final elem = param.declaredElement;
            final targetParamName = param.name?.lexeme ?? elem?.name ?? '';

            final bool isOptionalPositional = param.isOptionalPositional;
            final bool isRequiredPositional = param.isRequiredPositional;
            final bool isOptionalNamed = param.isOptionalNamed;
            final bool isRequiredNamed = param.isRequiredNamed;
            final bool isOptional = param.isOptional;
            // Check whether it is a child-related parameter
            final bool isChildChildrenOrSlivers =
            _caredWidgetParamName.contains(targetParamName);


            // Find the default value
            String defValue = await _findDefValue(
              param: param,
              collection: _collection,
              decl: decl,
            ) ??
                '';

            // Find the type
            String? type = await _findType(_context, decl, param, defValue);

            // Special handling
            if (constructorName.contains('RefreshIndicator') &&
                type == 'RefreshCallback') {
              type = 'm.$type';
            }
            // Sometimes the constructor is non-nullable, but the field is nullable
            // ex: SelectionRegistrarScope.registrar
            if (!isOptional) if (type.endsWith('?')) {
              type = type.substring(0, type.length - 1);
            }

            print('type:$type');

            if (isChildChildrenOrSlivers) {
              // Determine whether it is a single child Widget
              isSingleChild = targetParamName == 'child';
              print('$type, isSingleChild:$isSingleChild');

              // Currently does not support widget parameter being a Map
              pass = (isSingleChild == false &&
                  (type.startsWith('Map') ||
                      (type.startsWith('List') && !type.contains('Widget'))));
              if (pass) break;
            }

            if (isChildChildrenOrSlivers) {
              if (isRequiredPositional) {
                args.add('this');
              } else if (isOptionalPositional) {
                optionalArgs.add('this');
              } else if (isRequiredNamed) {
                namedArgs.insert(0, '${targetParamName}: this');
              } else if (isOptionalNamed) {
                namedArgs.insert(0, '${targetParamName}: this');
              }
              continue;
            }

            // If the type is non-nullable and has no default value, it must be required
            if (!type.endsWith('?') &&
                defValue.isEmpty &&
                !isRequiredPositional &&
                !isRequiredNamed) {
            } else if (isRequiredPositional) {
              params.add(
                  '$type $targetParamName${defValue.isNotEmpty ? ' = $defValue' : ''}');
              args.add('$targetParamName');
            } else if (isOptionalPositional) {
              optionalParams.add(
                  '$type $targetParamName${defValue.isNotEmpty ? ' = $defValue' : ''}');
              optionalArgs.add('$targetParamName');
            } else if (isRequiredNamed) {
              namedParams.add(
                  'required $type $targetParamName${defValue.isNotEmpty ? ' = $defValue' : ''}');
              namedArgs.add('${targetParamName}: $targetParamName');
            } else if (isOptionalNamed) {
              namedParams.add(
                  '$type $targetParamName${defValue.isNotEmpty ? ' = $defValue' : ''}');
              namedArgs.add('${targetParamName}: $targetParamName');
            }
          }

          // Whether to skip
          if (pass) continue;

          // function name
          String fnName = constructorName.split('.').mapIndexed(
                (index, element) {
              if (index == 0) return _lowerFirst(element);
              return element;
            },
          ).join('');

          // Add generics to function name
          if (decl.typeParameters?.typeParameters != null) {
            fnName = '$fnName<${decl.typeParameters?.typeParameters.join(', ')}>';
          }
          // Compose parameter sections
          final allParams = [
            ...params,
            if (optionalParams.isNotEmpty) '[${optionalParams.join(', ')},]',
            if (namedParams.isNotEmpty) '{${namedParams.join(', ')},}',
          ].join(', ');
          final allArgs = [
            ...args,
            if (optionalArgs.isNotEmpty) '${optionalArgs.join(', ')}',
            if (namedArgs.isNotEmpty) '${namedArgs.join(', ')}',
          ].join(', ') +
              ',';

          if (isSingleChild != null) {
            if (isSingleChild) {
              singleChildFns.add(
                  '  Widget $fnName($allParams) =>\n    $constructorName($allArgs);');
            } else {
              multiChildFns.add(
                  '  Widget $fnName($allParams) =>\n    $constructorName($allArgs);');
            }
          }
        }
        //if (focusClass.isNotEmpty) return;
      }

      final importBuffer = StringBuffer();
      final sortedImports = _imports.toList()..sort();
      for (final uri in sortedImports) {
        importBuffer.writeln('import $uri');
      }
      importBuffer.writeln();

      final out = StringBuffer();
      out.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
      out.writeln('// Generated by FlutterWidgetSkewerBuilder');
      out.writeln();
      out.write(importBuffer.toString());


      // Single-child extension
      out.writeln('/// Chain a Widget with other widget that takes a child parameter.');
      out.writeln('extension FlutterWidgetSkewer on Widget {');
      for (final s in singleChildFns) {
        out.writeln(s);
        out.writeln();
      }
      out.writeln('}');
      out.writeln();

      // Multi-child extension
      out.writeln('/// Converting a List<Widget> into a multi-child widget that takes a children or slivers parameter.');
      out.writeln('extension MultiChildFlutterWidgetSkewer on List<Widget> {');
      for (final s in multiChildFns) {
        out.writeln(s);
        out.writeln();
      }
      out.writeln('}');
      out.writeln();

      // const value
      out.writeln('/// const value');
      for (final s in constValue) {
        out.writeln(s);
        out.writeln();
      }
      out.writeln();

      final outputId = AssetId(buildStep.inputId.package,
          p.join('lib', 'gen/flutter_widget_skewer.g.dart'));
      await buildStep.writeAsString(outputId, out.toString());

      log.info(
          'Output written to ${outputId.path}（${singleChildFns.length} single, ${multiChildFns.length} multi）');
    }

    /// Find Flutter SDK path
    Future<String?> getFlutterSdkPath({String projectRoot = '.'}) async {
      try {
        // 1. fvm
        final fvmPath = Directory(p.join(projectRoot, '.fvm', 'flutter_sdk'));
        if (fvmPath.existsSync()) {
          final sdkPath = p.normalize(fvmPath.path);
          print('Get flutter SDK Path via fvm!\nFlutter SDK: $sdkPath',
              'getFlutterSdkPath');
          return sdkPath;
        }

        // 2. package_config.json
        final file = File('.dart_tool/package_config.json');
        if (!file.existsSync()) {
          throw Exception(
              '.dart_tool/package_config.json not found. Please run "flutter pub get" first.');
        }

        final json = jsonDecode(await file.readAsString());
        for (final pkg in json['packages']) {
          if (pkg['name'] == 'flutter') {
            // flutter URI → file system path.
            final rootUri = pkg['rootUri'] as String;
            final rootPath = rootUri.startsWith('file://')
                ? Uri.parse(rootUri).toFilePath()
                : rootUri;
            final sdkPath = '$rootPath/lib';
            print(
                'Get flutter SDK Path via package_config.json!\nFlutter SDK: $sdkPath',
                'getFlutterSdkPath');
            return sdkPath;
          }
        }

        // 3. FLUTTER_ROOT
        final flutterRoot = Platform.environment['FLUTTER_ROOT'];
        if (flutterRoot != null && flutterRoot.isNotEmpty) {
          final sdkPath = p.normalize(flutterRoot);
          print(
              'Get flutter SDK Path via evn [FLUTTER_ROOT]!\nFlutter SDK: $sdkPath',
              'getFlutterSdkPath');
        }

        // 4. which / where
        final result1 = await Process.run(
          Platform.isWindows ? 'where' : 'which',
          ['flutter'],
        );
        if (result1.exitCode == 0) {
          final flutterBin = (result1.stdout as String).trim().split('\n').first;
          final sdkPath =
              '${p.normalize(File(flutterBin).parent.parent.path)}/packages/flutter/lib';
          print(
              'Get flutter SDK Path via ${Platform.isWindows ? 'where' : 'which'}!\nFlutter SDK: $sdkPath',
              'getFlutterSdkPath');
          return sdkPath;
        }
      } catch (e) {
        stderr.writeln('getFlutterSdkPath error: $e');
      }
      return null;
    }

    /// Determine whether this is a target Widget class to analyze
    Future<bool> _isWidgetClassDeclaration(ClassDeclaration decl) async {
      // Filter out private classes
      if (decl.name.toString().startsWith('_')) return false;

      // Filter out abstract classes
      if (decl.abstractKeyword != null) return false;

      final cls = decl.declaredElement;
      if (cls == null) return false;

      print('className:${cls.name}', '_isWidgetClassDeclaration');

      // Must inherit from XxxWidget
      ClassDeclaration inheritsDecl = decl;
      bool? inheritsXXXWidget;
      if (decl.extendsClause == null) return false;
      while (inheritsXXXWidget == null) {
        String superClassName = inheritsDecl.extendsClause?.superclass.beginToken.toString() ?? '';
        print('superClassName:$superClassName', '_isWidgetClassDeclaration');
        if (superClassName.endsWith('Widget')) {
          inheritsXXXWidget = true;
          break;
        }
        final inheritsDeclTmp = _allDecl.firstWhereOrNull(
              (element) => element.declaredElement?.name == superClassName,
        );
        print('superClassName:$superClassName, ${inheritsDeclTmp?.declaredElement?.name}', '_isWidgetClassDeclaration');
        if (inheritsDeclTmp == null) {
          inheritsXXXWidget = false;
        } else {
          inheritsDecl = inheritsDeclTmp;
        }
      }
      print('inheritsXXXWidget:$inheritsXXXWidget', '_isWidgetClassDeclaration');
      if (!inheritsXXXWidget) return false;

      // Must have at least child / children
      bool? hasChildOrChildren;
      for (final member in decl.members) {
        if (_focusClass != null) if (cls.name != _focusClass) continue;
        if (member is! ConstructorDeclaration) continue;
        String constructorName = member.declaredElement!.displayName;
        // Ignored list
        if (_ignoreWidget.contains(constructorName)) continue;
        // Private constructor
        if (constructorName.contains('_')) continue;
        print('[$constructorName] constructor →', '_isWidgetClassDeclaration');
        print('path:${decl.declaredElement?.source.fullName}',
            '_isWidgetClassDeclaration');
        for (final param in member.parameters.parameters) {
          final elem = param.declaredElement;
          final targetParamName = param.name?.lexeme ?? elem?.name ?? '';
          final bool isChildChildrenOrSlivers =
          _caredWidgetParamName.contains(targetParamName);
          if (!isChildChildrenOrSlivers) continue;

          // Find the default value
          String defValue = await _findDefValue(
            param: param,
            collection: _collection,
            decl: decl,
          ) ??
              '';

          // Find the type
          String? type = await _findType(_context, decl, param, defValue);
          hasChildOrChildren = type.contains('Widget');
          break;
        }
        if (hasChildOrChildren != null) break;
      }

      print('${cls.name}, hasChildOrChildren:$hasChildOrChildren',
          '_isWidgetClassDeclaration');
      return hasChildOrChildren ?? false;
    }

    Future<String> _findType(AnalysisContext context, ClassDeclaration decl,
        FormalParameter param, String defValue) async {
      final elem = param.declaredElement;
      final targetParamName = param.name?.lexeme ?? elem?.name ?? '';
      final String targetParamSource = param.toSource();
      String? type;

      final bool isRequired = param.isRequired;
      final bool isSuper = param.declaredElement!.isSuperFormal;
      final bool isFinal = targetParamSource.contains('this.');
      final bool isNamed = param.isNamed;
      final bool isOptionalPositional = param.isOptionalPositional;
      final bool isRequiredPositional = param.isRequiredPositional;
      final bool isOptionalNamed = param.isOptionalNamed;
      final bool isRequiredNamed = param.isRequiredNamed;
      final bool isOptional = param.isOptional;

      print(
          'targetParamName:$targetParamName, ${targetParamSource}, isSuper:$isSuper, isFinal:$isFinal, isOptionalPositional:$isOptionalPositional, isRequiredPositional:$isRequiredPositional, isOptionalNamed:$isOptionalNamed, isRequiredNamed:$isRequiredNamed, isRequired:$isRequired, isOptional:$isOptional, isNamed:$isNamed, defValue:$defValue',
          '_findType');

      // Try to get the type
      if (!isSuper && !isFinal) {
        String sourceTmp = targetParamSource;
        // Remove the default value
        if (defValue.isNotEmpty) {
          sourceTmp = sourceTmp.split('=')[0].trim();
        }
        // Remove 'required'
        if (sourceTmp.startsWith('required ')) {
          sourceTmp = sourceTmp.replaceFirst('required ', '');
        }
        // Split by space and remove the targetParamName
        final sourceTmpList = sourceTmp.split(' ')
          ..removeWhere(
                (element) => element == targetParamName,
          );
        type = sourceTmpList.join(' ');
        print('sourceTmp:$sourceTmp, sourceTmpList:$sourceTmpList','_findType');

        print('0, $type','_findType');
      } else if (isFinal) {
        // This must be a final field
        for (var fd in decl.members) {
          if (fd is! FieldDeclaration) continue;

          for (var variable in fd.fields.variables) {
            final element = variable.declaredElement;
            if (element is FieldElement && element.name == targetParamName) {
              final typeNode = fd.fields.type;
              if (typeNode != null) {
                type = typeNode.toString();
              } else {
                type = element.type.getDisplayString();
              }
              if (type.contains('InvalidType')) {
                String code = fd.toSource();
                final tmp = code.split(' ');
                if (tmp.length != 3) continue;
                String paramName = tmp[2].replaceAll(';', '');
                if (paramName == targetParamName) {
                  type = tmp[1];
                }
              }
              break;
            }
          }
          if (type != null) break;
        }
        print('1.$targetParamName, $type','_findType');
      } else if (elem?.type != null &&
          elem!.type is! DynamicType &&
          !elem.type.toString().contains('InvalidType')) {
        type = elem.type.getDisplayString();
        print('2, $type','_findType');
      } else if (isSuper) {
        String superClassPath =
            decl.declaredElement!.supertype!.element.source.fullName;
        String superClassName = decl.declaredElement!.supertype!.element.name;

        ResolvedUnitResult result = await context.currentSession
            .getResolvedUnit(superClassPath) as ResolvedUnitResult;

        while (true) {
          print('superClassName:$superClassName, superClassPath:$superClassPath','_findType');
          final superDecl = result.unit.declarations.firstWhereOrNull(
                (element) {
              return superClassName == element.declaredElement?.name;
            },
          ) as ClassDeclaration?;
          print('find superclass: ${superDecl != null}','_findType');
          if (superDecl == null) break;
          // Whether a same-named parameter is found in the superclass constructor
          bool findSuperParam = false;
          for (final member in superDecl.members) {
            if (member is! ConstructorDeclaration) continue;
            for (final param in member.parameters.parameters) {
              final elem = param.declaredElement;
              final paramName = param.name?.lexeme ?? elem?.name ?? '';
              String paramSource = param.toSource();
              bool isRequired = param.isRequired;
              bool isSuper = param.declaredElement!.isSuperFormal;
              bool isFinal = paramSource.contains('this.');
              print(
                  'ParamName:$paramName, ${targetParamSource}, isSuper:$isSuper, isFinal:$isFinal, isRequired:$isRequired, defValue:$defValue','_findType');
              if (targetParamName != paramName) continue;
              findSuperParam = true;
              if (elem?.type != null &&
                  elem!.type is! DynamicType &&
                  !elem.type.toString().contains('InvalidType')) {
                type = elem.type.getDisplayString();
              } else if (isFinal) {
                // This must be a final field
                for (var fd in superDecl.members) {
                  if (fd is! FieldDeclaration) continue;
                  final tmp = fd.toSource().split(' ');
                  if (tmp.length != 3) continue;
                  String paramName = tmp[2].replaceAll(';', '');
                  print(
                      '$paramName. ${fd.toSource()}, paramName:$paramName, ${tmp[1]}','_findType');
                  if (paramName == targetParamName) {
                    type = tmp[1];
                    break;
                  }
                }
              }
              if (type != null) break;
            }
            if (findSuperParam) break;
          }
          if (type != null) break;
          // If we get here, it wasn't found; continue walking up the superclasses
          if (superDecl.declaredElement!.supertype == null) break;
          superClassName = superDecl.declaredElement!.supertype!.element.name;
          String nextSuperClassPath =
              superDecl.declaredElement!.supertype!.element.source.fullName;

          if (superClassPath != nextSuperClassPath) {
            superClassPath = nextSuperClassPath;
            result = await context.currentSession.getResolvedUnit(superClassPath)
            as ResolvedUnitResult;
          }
        }
        print('3, targetParamName:$targetParamName, $type','_findType');
      }

      if (type == null) type = 'dynamic';

      return type;
    }

    /// Find the parameter default value
    Future<String?> _findDefValue({
      required FormalParameter param,
      required AnalysisContextCollection collection,
      required ClassDeclaration decl,
    }) async {
      bool withPrivateConstValue(String? defValue) =>
          defValue?.split(' ').any(
                (element) => element.startsWith('_'),
          ) ??
              false;

      bool isSuper = param.declaredElement!.isSuperFormal;
      String? defValue = param.declaredElement?.defaultValueCode;

      if (!isSuper) {
        print('defValue:$defValue','_findDefValue');
        if (withPrivateConstValue(defValue)) {
          String classPath = decl.declaredElement!.source.fullName;
          print('classPath:${classPath}','_findDefValue');
          AnalysisContext context = collection.contextFor(classPath);
          ResolvedUnitResult result = await context.currentSession
              .getResolvedUnit(classPath) as ResolvedUnitResult;
          _findPrivateConstValue(result, decl, defValue!);
        }
        return defValue;
      }
      final superName =
      param.toSource().substring(6).split(' ')[0].trim(); // Remove 'super.' and the default value

      print('${decl.name}, ${param.name}','_findDefValue');
      ExtendsClause? ec = decl.extendsClause;

      while (true) {
        final superDecl = _allDecl.firstWhereOrNull((element) =>
        element.declaredElement!.name == ec?.superclass.name2.toString());
        print('_findDefValue find superclass: ${superDecl != null}','_findDefValue');
        if (superDecl == null) break;

        // Whether a same-named parameter is found in the superclass constructor
        bool findSuperParam = false;
        for (final member in superDecl.members) {
          if (member is! ConstructorDeclaration) continue;
          for (final param in member.parameters.parameters) {
            final elem = param.declaredElement;
            final name = param.name?.lexeme ?? elem?.name ?? '';
            //print('_findDefValue name:$name, superName:$superName, ${param.toSource()}');
            if (superName != name) continue;
            defValue = param.declaredElement?.defaultValueCode;
            findSuperParam = true;
          }
          if (findSuperParam) break;
        }
        if (defValue != null) {
          if (withPrivateConstValue(defValue)) {
            String superClassPath =
                decl.declaredElement!.supertype!.element.source.fullName;
            AnalysisContext context = collection.contextFor(superClassPath);
            ResolvedUnitResult result = await context.currentSession
                .getResolvedUnit(superClassPath) as ResolvedUnitResult;
            _findPrivateConstValue(result, superDecl, defValue);
          }
          break;
        }
        if (superDecl.declaredElement!.supertype == null) break;
        // If we get here, it wasn't found; continue walking up the superclasses
        ec = superDecl.extendsClause;
      }

      return defValue;
    }

    List<String> constValue = [];

    /// Values of const variables
    /// May be top-level or defined inside the class
    void _findPrivateConstValue(
        ResolvedUnitResult result, ClassDeclaration decl, String defValue) {
      print('_findPrivateConstValue defValue:$defValue','_findPrivateConstValue');

      // Find the private class
      if (defValue.endsWith('()')) {
        String className = defValue.split(' ').last.replaceAll('()', '');
        // Search top-level
        for (final decl in result.unit.declarations) {
          if (decl is! ClassDeclaration) continue;
          if (decl.name.toString() == className) {
            String code = decl.toSource();
            if (!constValue.contains(code)) constValue.add(code);
            return;
          }
        }
      } else {
        // Find static variables
        // Search top-level
        for (var declaration in result.unit.declarations) {
          if (declaration is TopLevelVariableDeclaration) {
            for (var variable in declaration.variables.variables) {
              if (variable.name.toString() == defValue) {
                String code = 'const ${variable.toSource()};';
                if (!constValue.contains(code)) {
                  constValue.add(code);
                  code
                      .split(' ')
                      .where(
                        (element) => element.startsWith('_'),
                  )
                      .forEach(
                        (element) {
                      _findPrivateConstValue(result, decl, element);
                    },
                  );
                }
                return;
              }
            }
          }
        }

        // Search in class or method/function
        for (var member in decl.members) {
          if (member is FieldDeclaration) {
            for (var variable in member.fields.variables) {
              print('${variable.name.toString()}');
              if (variable.name.toString() == defValue) {
                String code = 'const ${variable.toSource()};';
                if (!constValue.contains(code)) {
                  constValue.add(code);
                  code
                      .split(' ')
                      .where(
                        (element) => element.startsWith('_'),
                  )
                      .forEach(
                        (element) {
                      _findPrivateConstValue(result, decl, element);
                    },
                  );
                }
                return;
              }
            }
          } else if (member is MethodDeclaration) {
            if (member.name.toString() == defValue) {
              String code = member.toSource();
              // If it was a static method inside a class, it will be emitted at the top level, so remove 'static'
              if (member.isStatic) code = code.replaceAll('static', '').trim();
              if (!constValue.contains(code)) {
                constValue.add(code);
                code
                    .split(' ')
                    .where(
                      (element) => element.startsWith('_'),
                )
                    .forEach(
                      (element) {
                    _findPrivateConstValue(result, decl, element);
                  },
                );
              }
            }
          }
        }
      }
    }
  }