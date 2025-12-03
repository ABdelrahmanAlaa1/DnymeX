// ignore_for_file: unnecessary_null_comparison, invalid_use_of_protected_member

import 'package:anymex/screens/search/source_search_page.dart';
import 'package:anymex/utils/extension_utils.dart';
import 'package:anymex/utils/logger.dart';
import 'dart:async';
import 'dart:io';
import 'package:anymex/controllers/cacher/cache_controller.dart';
import 'package:anymex/controllers/service_handler/params.dart';
import 'package:anymex/controllers/service_handler/service_handler.dart';
import 'package:anymex/controllers/offline/offline_storage_controller.dart';
import 'package:anymex/controllers/services/widgets/widgets_builders.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:anymex/models/Service/base_service.dart';
import 'package:anymex/utils/function.dart';
import 'package:anymex/utils/repo_list_utils.dart';
import 'package:anymex/utils/storage_provider.dart';
import 'package:anymex/widgets/common/search_bar.dart';
import 'package:anymex/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/Aniyomi/AniyomiExtensions.dart';
import 'package:dartotsu_extension_bridge/Mangayomi/MangayomiExtensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:anymex/widgets/custom_widgets/anymex_progress.dart';
import 'package:get/get.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:hive/hive.dart';

final sourceController = Get.put(SourceController());

class SourceController extends GetxController implements BaseService {
  var availableExtensions = <Source>[].obs;
  var availableMangaExtensions = <Source>[].obs;
  var availableNovelExtensions = <Source>[].obs;

  var installedExtensions = <Source>[].obs;
  var activeSource = Rxn<Source>();

  var installedDownloaderExtensions = <Source>[].obs;

  var installedMangaExtensions = <Source>[].obs;
  var activeMangaSource = Rxn<Source>();

  var installedNovelExtensions = <Source>[].obs;
  var activeNovelSource = Rxn<Source>();

  var lastUpdatedSource = "".obs;

  final _animeSections = <Widget>[].obs;
  final _homeSections = <Widget>[].obs;
  final _mangaSections = <Widget>[].obs;
  final novelSections = <Widget>[].obs;

  final isExtensionsServiceAllowed = false.obs;
  final RxList<String> _activeAnimeRepo = <String>[].obs;
  final RxList<String> _activeMangaRepo = <String>[].obs;
  final RxList<String> _activeNovelRepo = <String>[].obs;
  final RxList<String> _activeAniyomiAnimeRepo = <String>[].obs;
  final RxList<String> _activeAniyomiMangaRepo = <String>[].obs;

  final RxBool shouldShowExtensions = false.obs;

  final Map<ItemType, Map<String, int>> _sourceUsage = {
    for (final type in ItemType.values) type: <String, int>{},
  };

  List<String> get activeAnimeRepo => _activeAnimeRepo;
  set activeAnimeRepo(List<String> value) {
    _activeAnimeRepo.assignAll(normalizeRepoList(value));
    saveRepoSettings();
  }

  List<String> get activeMangaRepo => _activeMangaRepo;
  set activeMangaRepo(List<String> value) {
    _activeMangaRepo.assignAll(normalizeRepoList(value));
    saveRepoSettings();
  }

  List<String> get activeNovelRepo => _activeNovelRepo;
  set activeNovelRepo(List<String> value) {
    _activeNovelRepo.assignAll(normalizeRepoList(value));
    saveRepoSettings();
  }

  List<String> get activeAniyomiAnimeRepo => _activeAniyomiAnimeRepo;
  set activeAniyomiAnimeRepo(List<String> value) {
    _activeAniyomiAnimeRepo.assignAll(normalizeRepoList(value));
    saveRepoSettings();
  }

  List<String> get activeAniyomiMangaRepo => _activeAniyomiMangaRepo;
  set activeAniyomiMangaRepo(List<String> value) {
    _activeAniyomiMangaRepo.assignAll(normalizeRepoList(value));
    saveRepoSettings();
  }

  bool appendRepoUrl({
    required ItemType type,
    required ExtensionType extensionType,
    required String repo,
  }) {
    final trimmed = repo.trim();
    if (trimmed.isEmpty) return false;

    switch (type) {
      case ItemType.anime:
        final before = List<String>.from(getAnimeRepo(extensionType));
        final updated = appendRepoEntry(before, trimmed);
        if (listEquals(before, updated)) return false;
        setAnimeRepo(updated, extensionType);
        return true;
      case ItemType.manga:
        final before = List<String>.from(getMangaRepo(extensionType));
        final updated = appendRepoEntry(before, trimmed);
        if (listEquals(before, updated)) return false;
        setMangaRepo(updated, extensionType);
        return true;
      case ItemType.novel:
        final before = List<String>.from(activeNovelRepo);
        final updated = appendRepoEntry(before, trimmed);
        if (listEquals(before, updated)) return false;
        activeNovelRepo = updated;
        return true;
    }
  }

  void setAnimeRepo(List<String> val, ExtensionType type) {
    final normalized = normalizeRepoList(val);
    if (type == ExtensionType.aniyomi) {
      Logger.i('Settings Aniyomi repo: $normalized');
      activeAniyomiAnimeRepo = normalized;
    } else {
      Logger.i('Settings Mangayomi repo: $normalized');
      activeAnimeRepo = normalized;
    }
  }

  void setMangaRepo(List<String> val, ExtensionType type) {
    final normalized = normalizeRepoList(val);
    if (type == ExtensionType.aniyomi) {
      activeAniyomiMangaRepo = normalized;
    } else {
      activeMangaRepo = normalized;
    }
  }

  List<String> getAnimeRepo(ExtensionType type) {
    if (type == ExtensionType.aniyomi) {
      Logger.i('Getting Aniyomi repo');
      return activeAniyomiAnimeRepo;
    } else {
      Logger.i('Getting Mangayomi repo');
      return activeAnimeRepo;
    }
  }

  List<String> getMangaRepo(ExtensionType type) {
    if (type == ExtensionType.aniyomi) {
      return activeAniyomiMangaRepo;
    } else {
      return activeMangaRepo;
    }
  }

  void saveRepoSettings() {
    final box = Hive.box('themeData');
    box.put("activeAnimeRepo", _activeAnimeRepo.toList());
    box.put("activeMangaRepo", _activeMangaRepo.toList());
    box.put("activeNovelRepo", _activeNovelRepo.toList());
    box.put("activeAniyomiAnimeRepo", _activeAniyomiAnimeRepo.toList());
    box.put("activeAniyomiMangaRepo", _activeAniyomiMangaRepo.toList());
    shouldShowExtensions.value = [
      _activeAnimeRepo,
      _activeAniyomiAnimeRepo,
      _activeMangaRepo,
      _activeAniyomiMangaRepo,
      _activeNovelRepo,
      installedExtensions,
      installedMangaExtensions,
      installedNovelExtensions,
    ].any((e) => e.isNotEmpty);
  }

  @override
  void onInit() {
    super.onInit();

    _initialize();
  }

  void _initialize() async {
    isar = await StorageProvider().initDB(null);
    await DartotsuExtensionBridge().init(isar, 'AnymeX');

    await initExtensions();

    if (Get.find<ServiceHandler>().serviceType.value ==
        ServicesType.extensions) {
      fetchHomePage();
    }
  }

  Future<List<Source>> _getInstalledExtensions(
      Future<List<Source>> Function() fetchFn) async {
    return await fetchFn();
  }

  List<Source> _getAvailableExtensions(List<Source> Function() fetchFn) {
    return fetchFn();
  }

  Future<void> sortAnimeExtensions() async {
    final types = ExtensionType.values.where((e) {
      if (!Platform.isAndroid && e == ExtensionType.aniyomi) return false;
      return true;
    });

    final installed = <Source>[];
    final available = <Source>[];

    for (final type in types) {
      final manager = type.getManager();
      installed.addAll(await _getInstalledExtensions(
          () => manager.getInstalledAnimeExtensions()));
      available.addAll(_getAvailableExtensions(
          () => manager.availableAnimeExtensions.value));
    }

    installedExtensions.value = installed;
    availableExtensions.value = available;

    installedDownloaderExtensions.value = installed
        .where((e) => e.name?.contains('Downloader') ?? false)
        .toList();
  }

  Future<void> sortMangaExtensions() async {
    final types = ExtensionType.values.where((e) {
      if (!Platform.isAndroid && e == ExtensionType.aniyomi) return false;
      return true;
    });

    final installed = <Source>[];
    final available = <Source>[];

    for (final type in types) {
      final manager = type.getManager();
      installed.addAll(await _getInstalledExtensions(
          () => manager.getInstalledMangaExtensions()));
      available.addAll(_getAvailableExtensions(
          () => manager.availableMangaExtensions.value));
    }

    installedMangaExtensions.value = installed;
    availableMangaExtensions.value = available;
  }

  Future<void> sortNovelExtensions() async {
    final types = ExtensionType.values.where((e) {
      if (!Platform.isAndroid && e == ExtensionType.aniyomi) return false;
      return true;
    });

    final installed = <Source>[];
    final available = <Source>[];

    for (final type in types) {
      final manager = type.getManager();
      installed.addAll(await _getInstalledExtensions(
          () => manager.getInstalledNovelExtensions()));
      available.addAll(_getAvailableExtensions(
          () => manager.availableNovelExtensions.value));
    }

    installedNovelExtensions.value = installed;
    availableNovelExtensions.value = available;
  }

  Future<void> sortAllExtensions() async {
    await Future.wait([
      sortAnimeExtensions(),
      sortMangaExtensions(),
      sortNovelExtensions(),
    ]);
  }

  Future<void> initExtensions({bool refresh = true}) async {
    try {
      await sortAllExtensions();
      final box = Hive.box('themeData');
      final savedActiveSourceId =
          box.get('activeSourceId', defaultValue: '') as String?;
      final savedActiveMangaSourceId =
          box.get('activeMangaSourceId', defaultValue: '') as String;
      final savedActiveNovelSourceId =
          box.get('activeNovelSourceId', defaultValue: '') as String;
      isExtensionsServiceAllowed.value =
          box.get('extensionsServiceAllowed', defaultValue: false);

      activeSource.value = installedExtensions.firstWhereOrNull(
          (source) => source.id.toString() == savedActiveSourceId);
      activeMangaSource.value = installedMangaExtensions.firstWhereOrNull(
          (source) => source.id.toString() == savedActiveMangaSourceId);
      activeNovelSource.value = installedNovelExtensions.firstWhereOrNull(
          (source) => source.id.toString() == savedActiveNovelSourceId);

      activeSource.value ??= installedExtensions.firstOrNull;
      activeMangaSource.value ??= installedMangaExtensions.firstOrNull;
      activeNovelSource.value ??= installedNovelExtensions.firstOrNull;

      var animeRepo = box.get("activeAnimeRepo");
      if (animeRepo is String && animeRepo.isNotEmpty) {
        _activeAnimeRepo.assignAll(normalizeRepoList([animeRepo]));
      } else if (animeRepo is List) {
        _activeAnimeRepo
            .assignAll(normalizeRepoList(animeRepo.cast<String>()));
      }

      var mangaRepo = box.get("activeMangaRepo");
      if (mangaRepo is String && mangaRepo.isNotEmpty) {
        _activeMangaRepo.assignAll(normalizeRepoList([mangaRepo]));
      } else if (mangaRepo is List) {
        _activeMangaRepo
            .assignAll(normalizeRepoList(mangaRepo.cast<String>()));
      }

      var novelRepo = box.get("activeNovelRepo");
      if (novelRepo is String && novelRepo.isNotEmpty) {
        _activeNovelRepo.assignAll(normalizeRepoList([novelRepo]));
      } else if (novelRepo is List) {
        _activeNovelRepo
            .assignAll(normalizeRepoList(novelRepo.cast<String>()));
      }

      var aniyomiAnimeRepo = box.get("activeAniyomiAnimeRepo");
      if (aniyomiAnimeRepo is String && aniyomiAnimeRepo.isNotEmpty) {
        _activeAniyomiAnimeRepo
            .assignAll(normalizeRepoList([aniyomiAnimeRepo]));
      } else if (aniyomiAnimeRepo is List) {
        _activeAniyomiAnimeRepo
            .assignAll(normalizeRepoList(aniyomiAnimeRepo.cast<String>()));
      }

      var aniyomiMangaRepo = box.get("activeAniyomiMangaRepo");
      if (aniyomiMangaRepo is String && aniyomiMangaRepo.isNotEmpty) {
        _activeAniyomiMangaRepo
            .assignAll(normalizeRepoList([aniyomiMangaRepo]));
      } else if (aniyomiMangaRepo is List) {
        _activeAniyomiMangaRepo
            .assignAll(normalizeRepoList(aniyomiMangaRepo.cast<String>()));
      }

      shouldShowExtensions.value = [
        _activeAnimeRepo,
        _activeAniyomiAnimeRepo,
        _activeMangaRepo,
        _activeAniyomiMangaRepo,
        _activeNovelRepo,
        installedExtensions,
        installedMangaExtensions,
        installedNovelExtensions,
      ].any((e) => e.isNotEmpty);

      _loadSourceUsage();

      Logger.i('Extensions initialized.');
    } catch (e) {
      Logger.i('Error initializing extensions: $e');
    }
  }

  bool isEmpty(dynamic val) => val.isEmpty;

  void setActiveSource(Source source) {
    if (source.itemType == ItemType.manga) {
      activeMangaSource.value = source;
      Hive.box('themeData').put('activeMangaSourceId', source.id);
      lastUpdatedSource.value = 'MANGA';
    } else if (source.itemType == ItemType.anime) {
      activeSource.value = source;
      Hive.box('themeData').put('activeSourceId', source.id);
      lastUpdatedSource.value = 'ANIME';
    } else {
      activeNovelSource.value = source;
      Hive.box('themeData').put('activeNovelSourceId', source.id);
      lastUpdatedSource.value = 'NOVEL';
    }
  }

  Box<dynamic>? _getPreferenceBox() {
    if (!Hive.isBoxOpen('preferences')) return null;
    return Hive.box<dynamic>('preferences');
  }

  String _mediaSourceKey({
    required ItemType type,
    required Media media,
  }) {
    final service = media.serviceType.name;
    return 'source_selection_${type.name}_${service}_${media.id}';
  }

  void rememberSourceSelectionForMedia({
    required ItemType type,
    required Media media,
    required Source source,
  }) {
    final prefs = _getPreferenceBox();
    final sourceId = source.id?.toString();
    if (prefs == null || sourceId == null || sourceId.isEmpty) return;

    prefs.put(_mediaSourceKey(type: type, media: media), sourceId);
  }

  String _usagePreferenceKey(ItemType type) => 'source_usage_${type.name}';

  void _loadSourceUsage() {
    final prefs = _getPreferenceBox();
    if (prefs == null) return;
    for (final type in ItemType.values) {
      final raw = prefs.get(_usagePreferenceKey(type));
      if (raw is Map) {
        final sanitized = <String, int>{};
        raw.forEach((key, value) {
          final count = value is int ? value : int.tryParse(value.toString());
          if (count != null) {
            sanitized[key.toString()] = count;
          }
        });
        _sourceUsage[type] = sanitized;
      }
    }
  }

  void _saveSourceUsage(ItemType type) {
    final prefs = _getPreferenceBox();
    if (prefs == null) return;
    prefs.put(_usagePreferenceKey(type), _sourceUsage[type]);
  }

  void recordSourceUsage({required ItemType type, required Source source}) {
    final sourceId = source.id?.toString();
    if (sourceId == null || sourceId.isEmpty) return;
    final usage = _sourceUsage[type] ?? <String, int>{};
    usage[sourceId] = (usage[sourceId] ?? 0) + 1;
    _sourceUsage[type] = usage;
    _saveSourceUsage(type);
  }

  List<Source> getTopSources(ItemType type, {int limit = 5}) {
    final usage = _sourceUsage[type] ?? const <String, int>{};
    final installed = List<Source>.from(getInstalledExtensions(type));
    installed.sort((a, b) {
      final aCount = usage[a.id?.toString()] ?? 0;
      final bCount = usage[b.id?.toString()] ?? 0;
      if (bCount != aCount) {
        return bCount.compareTo(aCount);
      }
      return (a.name ?? '').compareTo(b.name ?? '');
    });
    return installed
        .where((source) => (usage[source.id?.toString()] ?? 0) > 0)
        .take(limit)
        .toList();
  }

  List<Source> getPrioritizedSources(ItemType type) {
    final topSources = getTopSources(type);
    final favoriteIds = topSources
        .map((source) => source.id?.toString())
        .whereType<String>()
        .toSet();
    final others = getInstalledExtensions(type)
        .where((source) =>
            !favoriteIds.contains(source.id?.toString() ?? ''))
        .toList();
    return [...topSources, ...others];
  }

  Source? applyStoredSourceSelection({
    required ItemType type,
    required Media media,
  }) {
    final prefs = _getPreferenceBox();
    if (prefs == null) return null;

    final key = _mediaSourceKey(type: type, media: media);
    final savedId = prefs.get(key)?.toString();

    if (savedId == null || savedId.isEmpty) {
      return null;
    }

    final source = getInstalledExtensions(type)
        .firstWhereOrNull((s) => s.id.toString() == savedId);

    if (source != null) {
      setActiveSource(source);
      return source;
    }

    prefs.delete(key);
    return null;
  }

  List<Source> getInstalledExtensions(ItemType type) {
    switch (type) {
      case ItemType.anime:
        return installedExtensions;
      case ItemType.manga:
        return installedMangaExtensions;
      case ItemType.novel:
        return installedNovelExtensions;
    }
  }

  Source? getActiveSourceForType(ItemType type) {
    switch (type) {
      case ItemType.anime:
        return activeSource.value;
      case ItemType.manga:
        return activeMangaSource.value;
      case ItemType.novel:
        return activeNovelSource.value;
    }
  }

  void _setActiveSourceForType(ItemType type, Source source) {
    switch (type) {
      case ItemType.anime:
        activeSource.value = source;
        Hive.box('themeData').put('activeSourceId', source.id);
        break;
      case ItemType.manga:
        activeMangaSource.value = source;
        Hive.box('themeData').put('activeMangaSourceId', source.id);
        break;
      case ItemType.novel:
        activeNovelSource.value = source;
        Hive.box('themeData').put('activeNovelSourceId', source.id);
        break;
    }
  }

  Source? cycleToNextSource(ItemType type) {
    final sources = getPrioritizedSources(type);
    if (sources.length <= 1) return null;

    final favorites = getTopSources(type);
    final favoriteIds = favorites
        .map((source) => source.id?.toString())
        .whereType<String>()
        .toSet();

    final current = getActiveSourceForType(type);
    final currentId = current?.id?.toString();
    final currentIndex = currentId == null
        ? -1
        : sources.indexWhere((source) => source.id?.toString() == currentId);

    int nextIndex;
    if (currentIndex == -1) {
      nextIndex = 0;
    } else if (!favoriteIds.contains(currentId ?? '') &&
        favorites.isNotEmpty) {
      nextIndex = 0;
      if (sources[nextIndex].id?.toString() == currentId) {
        nextIndex = (nextIndex + 1) % sources.length;
      }
    } else {
      nextIndex = (currentIndex + 1) % sources.length;
    }

    final nextSource = sources[nextIndex];
    if (nextSource.id?.toString() == currentId) {
      return null;
    }

    _setActiveSourceForType(type, nextSource);
    recordSourceUsage(type: type, source: nextSource);
    return nextSource;
  }

  List<Source> getAvailableExtensions(ItemType type) {
    switch (type) {
      case ItemType.anime:
        return availableExtensions;
      case ItemType.manga:
        return availableMangaExtensions;
      case ItemType.novel:
        return availableNovelExtensions;
    }
  }

  Future<void> fetchRepos() async {
    final extenionTypes = ExtensionType.values.where((e) {
      if (!Platform.isAndroid) {
        if (e == ExtensionType.aniyomi) {
          return false;
        }
      }
      return true;
    }).toList();
    Logger.i(extenionTypes.length.toString());
    if (Platform.isAndroid) {
      Get.put(AniyomiExtensions(), tag: 'AniyomiExtensions');
    }
    Get.put(MangayomiExtensions(), tag: 'MangayomiExtensions');
    for (var type in extenionTypes) {
      await type
          .getManager()
          .fetchAvailableAnimeExtensions(getAnimeRepo(type));
      await type
          .getManager()
          .fetchAvailableMangaExtensions(getMangaRepo(type));
      await type.getManager().fetchAvailableNovelExtensions(
        activeNovelRepo,
      );
    }
    await initExtensions();
  }

  Source? getExtensionByName(String name) {
    final selectedSource = installedExtensions.firstWhereOrNull((source) =>
        '${source.name} (${source.lang?.toUpperCase()})' == name ||
        source.name == name);

    if (selectedSource != null) {
      activeSource.value = selectedSource;
      Hive.box('themeData').put('activeSourceId', selectedSource.id);
      return activeSource.value;
    }
    lastUpdatedSource.value = 'ANIME';
    return null;
  }

  Source? getMangaExtensionByName(String name) {
    final selectedMangaSource = installedMangaExtensions.firstWhereOrNull(
        (source) =>
            '${source.name} (${source.lang?.toUpperCase()})' == name ||
            source.name == name);

    if (selectedMangaSource != null) {
      activeMangaSource.value = selectedMangaSource;
      Hive.box('themeData').put('activeMangaSourceId', selectedMangaSource.id);
      return activeMangaSource.value;
    }
    lastUpdatedSource.value = 'MANGA';
    return null;
  }

  Source? getNovelExtensionByName(String name) {
    final selectedNovelSource = installedNovelExtensions.firstWhereOrNull(
        (source) =>
            '${source.name} (${source.lang?.toUpperCase()})' == name ||
            source.name == name);

    if (selectedNovelSource != null) {
      activeNovelSource.value = selectedNovelSource;
      Hive.box('themeData').put('activeNovelSourceId', selectedNovelSource.id);
      return activeNovelSource.value;
    }
    lastUpdatedSource.value = 'NOVEL';
    return null;
  }

  void _initializeEmptySections() {
    final offlineStorage = Get.find<OfflineStorageController>();
    _animeSections.value = [const Center(child: AnymexProgressIndicator())];
    _mangaSections.value = [const Center(child: AnymexProgressIndicator())];
    novelSections.value = [const Center(child: AnymexProgressIndicator())];
    _homeSections.value = [
      Obx(
        () => buildSection(
            "Continue Watching",
            offlineStorage.animeLibrary
                .where((e) => e.serviceIndex == ServicesType.extensions.index)
                .toList(),
            variant: DataVariant.offline),
      ),
      Obx(() {
        return buildSection(
            "Continue Reading",
            offlineStorage.mangaLibrary
                .where((e) => e.serviceIndex == ServicesType.extensions.index)
                .toList(),
            variant: DataVariant.offline,
            type: ItemType.manga);
      }),
      Obx(() {
        return buildSection(
            "Continue Reading",
            offlineStorage.mangaLibrary
                .where((e) => e.serviceIndex == ServicesType.extensions.index)
                .toList(),
            variant: DataVariant.offline,
            type: ItemType.manga);
      }),
    ];
  }

  @override
  RxList<Widget> animeWidgets(BuildContext context) => [
        Obx(() {
          return Column(
            children: _animeSections.value,
          );
        })
      ].obs;

  @override
  RxList<Widget> homeWidgets(BuildContext context) => [
        Obx(() {
          return Column(
            children: _homeSections.value,
          );
        })
      ].obs;

  @override
  RxList<Widget> mangaWidgets(BuildContext context) => [
        Obx(() {
          return Column(
            children: [..._mangaSections.value, ...novelSections.value],
          );
        })
      ].obs;

  Future<void> initNovelExtensions() async {
    if (novelSections.isNotEmpty) return;
    novelSections.value = [
      const SizedBox(),
    ];
    for (final source in installedNovelExtensions) {
      _fetchSourceData(source,
          targetSections: novelSections, type: ItemType.novel);
    }
  }

  @override
  Future<void> fetchHomePage() async {
    try {
      _initializeEmptySections();

      for (final source in installedExtensions) {
        _fetchSourceData(source,
            targetSections: _animeSections, type: ItemType.anime);
      }

      for (final source in installedMangaExtensions) {
        _fetchSourceData(source,
            targetSections: _mangaSections, type: ItemType.manga);
      }

      initNovelExtensions();

      Logger.i('Fetched home page data.');
    } catch (error) {
      Logger.i('Error in fetchHomePage: $error');
      errorSnackBar('Failed to fetch data from sources.');
    }
  }

  Future<void> _fetchSourceData(
    Source source, {
    required RxList<Widget> targetSections,
    required ItemType type,
  }) async {
    try {
      final future = source.methods.getPopular(1).then((result) => result.list);

      final newSection = buildFutureSection(
        source.name ?? '??',
        future,
        type: type,
        variant: DataVariant.extension,
        source: source,
      );

      if (targetSections.first is Center && type != ItemType.novel) {
        targetSections.value = [];
        targetSections.add(CustomSearchBar(
          disableIcons: true,
          onSubmitted: (v) {
            SourceSearchPage(initialTerm: v, type: type).go();
          },
        ));
      }
      targetSections.add(newSection);

      Logger.i('Data fetched and updated for ${source.name}');
    } catch (e) {
      Logger.i('Error fetching data from ${source.name}: $e');
    }
  }

  @override
  Future<Media> fetchDetails(FetchDetailsParams params) async {
    final id = params.id;

    final isAnime = lastUpdatedSource.value == "ANIME";
    final data =
        await (!isAnime ? activeMangaSource.value! : activeSource.value!)
            .methods
            .getDetail(DMedia.withUrl(id));

    if (serviceHandler.serviceType.value != ServicesType.extensions) {
      cacheController.addCache(data.toJson());
    }
    return Media.froDMedia(data, isAnime ? ItemType.anime : ItemType.manga);
  }

  @override
  Future<List<Media>> search(SearchParams params) async {
    final source =
        params.isManga ? activeMangaSource.value : activeSource.value;
    final data = (await source!.methods.search(params.query, 1, [])).list;
    return data
        .map((e) => Media.froDMedia(
            e, params.isManga ? ItemType.manga : ItemType.anime))
        .toList();
  }
}
