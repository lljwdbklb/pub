// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../io.dart';
import '../package.dart';
import '../pubspec.dart';
import '../source.dart';
import '../system_cache.dart';
import '../utils.dart';

/// A package [Source] that gets packages from a given local file path.
class PathSource extends Source {
  final name = 'path';

  BoundSource bind(SystemCache systemCache) =>
      new BoundPathSource(this, systemCache);

  /// Given a valid path reference description, returns the file path it
  /// describes.
  ///
  /// This returned path may be relative or absolute and it is up to the caller
  /// to know how to interpret a relative path.
  String pathFromDescription(description) => description["path"];

  /// Returns a reference to a path package named [name] at [path].
  PackageRef refFor(String name, String path) {
    return new PackageRef(name, 'path', {
      "path": path,
      "relative": p.isRelative(path)
    });
  }

  /// Returns an ID for a path package with the given [name] and [version] at
  /// [path].
  PackageId idFor(String name, Version version, String path) {
    return new PackageId(name, 'path', version, {
      "path": path,
      "relative": p.isRelative(path)
    });
  }

  bool descriptionsEqual(description1, description2) {
    // Compare real paths after normalizing and resolving symlinks.
    var path1 = canonicalize(description1["path"]);
    var path2 = canonicalize(description2["path"]);
    return path1 == path2;
  }

  /// Parses a path dependency.
  ///
  /// This takes in a path string and returns a map. The "path" key will be the
  /// original path but resolved relative to the containing path. The
  /// "relative" key will be `true` if the original path was relative.
  PackageRef parseRef(String name, description, {String containingPath}) {
    if (description is! String) {
      throw new FormatException("The description must be a path string.");
    }

    // Resolve the path relative to the containing file path, and remember
    // whether the original path was relative or absolute.
    var isRelative = p.isRelative(description);
    if (isRelative) {
      // Relative paths coming from pubspecs that are not on the local file
      // system aren't allowed. This can happen if a hosted or git dependency
      // has a path dependency.
      if (containingPath == null) {
        throw new FormatException('"$description" is a relative path, but this '
            'isn\'t a local pubspec.');
      }

      description = p.normalize(
          p.join(p.dirname(containingPath), description));
    }

    return new PackageRef(name, this.name, {
      "path": description,
      "relative": isRelative
    });
  }

  PackageId parseId(String name, Version version, description) {
    if (description is! Map) {
      throw new FormatException("The description must be a map.");
    }

    if (description["path"] is! String) {
      throw new FormatException("The 'path' field of the description must "
          "be a string.");
    }

    if (description["relative"] is! bool) {
      throw new FormatException("The 'relative' field of the description "
          "must be a boolean.");
    }

    return new PackageId(name, this.name, version, description);
  }

  /// Serializes path dependency's [description].
  ///
  /// For the descriptions where `relative` attribute is `true`, tries to make
  /// `path` relative to the specified [containingPath].
  dynamic serializeDescription(String containingPath, description) {
    if (description["relative"]) {
      return {
        "path": p.relative(description['path'], from: containingPath),
        "relative": true
      };
    }
    return description;
  }

  /// Converts a parsed relative path to its original relative form.
  String formatDescription(String containingPath, description) {
    var sourcePath = description["path"];
    if (description["relative"]) {
      sourcePath = p.relative(description['path'], from: containingPath);
    }

    return sourcePath;
  }
}

/// The [BoundSource] for [PathSource].
class BoundPathSource extends BoundSource {
  final PathSource source;

  final SystemCache systemCache;

  BoundPathSource(this.source, this.systemCache);

  Future<List<PackageId>> doGetVersions(PackageRef ref) async {
    // There's only one package ID for a given path. We just need to find the
    // version.
    var pubspec = _loadPubspec(ref);
    var id = new PackageId(
        ref.name, source.name, pubspec.version, ref.description);
    memoizePubspec(id, pubspec);
    return [id];
  }

  Future<Pubspec> doDescribe(PackageId id) async => _loadPubspec(id.toRef());

  Pubspec _loadPubspec(PackageRef ref) {
    var dir = _validatePath(ref.name, ref.description);
    return new Pubspec.load(dir, systemCache.sources, expectedName: ref.name);
  }

  Future get(PackageId id, String symlink) {
    return new Future.sync(() {
      var dir = _validatePath(id.name, id.description);
      createPackageSymlink(id.name, dir, symlink,
          relative: id.description["relative"]);
    });
  }

  String getDirectory(PackageId id) => id.description["path"];

  /// Ensures that [description] is a valid path description and returns a
  /// normalized path to the package.
  ///
  /// It must be a map, with a "path" key containing a path that points to an
  /// existing directory. Throws an [ApplicationException] if the path is
  /// invalid.
  String _validatePath(String name, description) {
    var dir = description["path"];

    if (dirExists(dir)) return dir;

    if (fileExists(dir)) {
      fail('Path dependency for package $name must refer to a directory, '
           'not a file. Was "$dir".');
    }

    throw new PackageNotFoundException(
        'Could not find package $name at "$dir".');
  }
}
