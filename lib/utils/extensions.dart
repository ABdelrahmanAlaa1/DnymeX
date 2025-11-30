import 'package:anymex/controllers/source/source_controller.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:get/get.dart';

class Extensions {
  final settings = Get.put(SourceController());

  Future<bool> addRepo(ItemType type, String repo, ExtensionType ext) async {
    final didAppend = settings.appendRepoUrl(
      type: type,
      extensionType: ext,
      repo: repo,
    );

    if (didAppend) {
      await settings.fetchRepos();
    }

    return didAppend;
  }
}
