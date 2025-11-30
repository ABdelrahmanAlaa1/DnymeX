import 'dart:io';

import 'package:anymex/utils/extensions.dart';
import 'package:anymex/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';

class Deeplink {
  static Future<void> handleDeepLink(Uri uri) async {
    if (uri.host != 'add-repo') return;
    ExtensionType extType;
    String? repoUrl;
    String? mangaUrl;
    String? novelUrl;

    if (Platform.isAndroid) {
      switch (uri.scheme.toLowerCase()) {
        case 'aniyomi':
          extType = ExtensionType.aniyomi;
          repoUrl = uri.queryParameters["url"]?.trim();
          break;
        case 'tachiyomi':
          extType = ExtensionType.aniyomi;
          mangaUrl = uri.queryParameters["url"]?.trim();
          break;
        default:
          extType = ExtensionType.mangayomi;
          repoUrl =
              (uri.queryParameters["url"] ?? uri.queryParameters['anime_url'])
                  ?.trim();
          mangaUrl = uri.queryParameters["manga_url"]?.trim();
          novelUrl = uri.queryParameters["novel_url"]?.trim();
      }
    } else {
      extType = ExtensionType.mangayomi;
      repoUrl = (uri.queryParameters["url"] ?? uri.queryParameters['anime_url'])
          ?.trim();
      mangaUrl = uri.queryParameters["manga_url"]?.trim();
      novelUrl = uri.queryParameters["novel_url"]?.trim();
    }

    final manager = Extensions();
    final futures = <Future<bool>>[];

    if (_hasValue(repoUrl)) {
      futures.add(manager.addRepo(ItemType.anime, repoUrl!, extType));
    }

    if (_hasValue(mangaUrl)) {
      futures.add(manager.addRepo(ItemType.manga, mangaUrl!, extType));
    }

    if (_hasValue(novelUrl)) {
      futures.add(manager.addRepo(ItemType.novel, novelUrl!, extType));
    }

    if (futures.isEmpty) {
      snackBar("Missing required parameters in the link.");
      return;
    }

    final additions = await Future.wait(futures);
    if (additions.any((added) => added)) {
      snackBar("Added Repo Links Successfully!");
    } else {
      snackBar("Repositories already added. Nothing new to do.");
    }
  }

  static bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;
  }
}
