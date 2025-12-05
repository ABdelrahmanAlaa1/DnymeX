import 'dart:convert';
import 'dart:io';

import 'package:anymex/controllers/source/source_controller.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:anymex/models/Offline/Hive/chapter.dart';
import 'package:anymex/models/Offline/Hive/episode.dart' as hive;
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:anymex/utils/logger.dart';
import 'package:anymex/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/Models/DEpisode.dart';
import 'package:dartotsu_extension_bridge/Models/Video.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DownloadController extends GetxController {
  static const String downloadedSourceValue = '__anymex_downloaded__';
  static const String downloadedSourceLabel = 'Downloaded';
  static const int _fullChapterCaptureThreshold = 2;
  static const String _fallbackUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

  DownloadController() {
    _baseDirFuture = _prepareBaseDirectory();
  }

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  late final Future<Directory> _baseDirFuture;

  final RxMap<String, double> _progress = <String, double>{}.obs;
  RxMap<String, double> get progress => _progress;

  final RxMap<String, DownloadProgressContext> _progressContexts =
      <String, DownloadProgressContext>{}.obs;
  RxMap<String, DownloadProgressContext> get progressContexts => _progressContexts;

  final Rx<Set<String>> _cancelRequests = Rx<Set<String>>({});
  final Map<String, Set<CancelToken>> _activeCancelTokens = {};

  double? getEpisodeProgress(String mediaId, String episodeNumber) {
    return _progress[_downloadKey(
        type: ItemType.anime, mediaId: mediaId, number: _episodeKeyValue(episodeNumber))];
  }

  double? getChapterProgress(String mediaId, num? chapterNumber) {
    if (chapterNumber == null) return null;
    return _progress[
        _downloadKey(type: ItemType.manga, mediaId: mediaId, number: chapterNumber)];
  }

  void _updateProgress(String key, double value) {
    _progress[key] = value.clamp(0.0, 1.0);
    _progress.refresh();
  }

  void _clearProgress(String key) {
    if (_progress.remove(key) != null) {
      _progress.refresh();
    }
  }

  void _registerContext(String key, DownloadProgressContext context) {
    _progressContexts[key] = context;
    _progressContexts.refresh();
  }

  void _removeContext(String key) {
    if (_progressContexts.remove(key) != null) {
      _progressContexts.refresh();
    }
  }

  Future<bool> cancelActiveDownload(String key) async {
    return _requestCancellation(key, showFeedback: true);
  }

  Future<bool> cancelEpisodeDownload(String mediaId, String episodeNumber) {
    final key = _downloadKey(
      type: ItemType.anime,
      mediaId: mediaId,
      number: _episodeKeyValue(episodeNumber),
    );
    return _requestCancellation(key, showFeedback: true);
  }

  Future<bool> cancelChapterDownload(String mediaId, num? chapterNumber) {
    if (chapterNumber == null) return Future.value(false);
    final key = _downloadKey(
      type: ItemType.manga,
      mediaId: mediaId,
      number: chapterNumber,
    );
    return _requestCancellation(key, showFeedback: true);
  }

  Future<bool> _requestCancellation(String key, {bool showFeedback = false}) async {
    if (!_activeDownloads.value.contains(key)) {
      if (showFeedback) {
        infoSnackBar('Download already finished.');
      }
      return false;
    }

    final set = _cancelRequests.value;
    if (set.add(key)) {
      _cancelRequests.refresh();
      final tokens = _activeCancelTokens[key];
      if (tokens != null) {
        for (final token in tokens.toList()) {
          if (!token.isCancelled) {
            token.cancel('cancelled');
          }
        }
      }
      if (showFeedback) {
        infoSnackBar('Canceling download…');
      }
    } else if (showFeedback) {
      infoSnackBar('Cancellation already requested.');
    }

    return true;
  }

  void _registerCancelToken(String key, CancelToken token) {
    final set = _activeCancelTokens.putIfAbsent(key, () => <CancelToken>{});
    set.add(token);
  }

  void _releaseCancelToken(String key, CancelToken token) {
    final set = _activeCancelTokens[key];
    if (set == null) return;
    set.remove(token);
    if (set.isEmpty) {
      _activeCancelTokens.remove(key);
    }
  }

  void _clearCancellationState(String key) {
    final set = _cancelRequests.value;
    if (set.remove(key)) {
      _cancelRequests.refresh();
    }
    _activeCancelTokens.remove(key);
  }

  void _throwIfCancelled(String key) {
    if (_cancelRequests.value.contains(key)) {
      throw DownloadCancelledException(key);
    }
  }

  final Rx<Set<String>> _activeDownloads = Rx<Set<String>>({});
  Set<String> get activeDownloads => _activeDownloads.value;

  final RxMap<String, List<DownloadedChapter>> _chapterCache =
    <String, List<DownloadedChapter>>{}.obs;
  RxMap<String, List<DownloadedChapter>> get chapterCache => _chapterCache;

  final RxMap<String, List<DownloadedEpisode>> _episodeCache =
    <String, List<DownloadedEpisode>>{}.obs;
  RxMap<String, List<DownloadedEpisode>> get episodeCache => _episodeCache;

  Future<Directory> _prepareBaseDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, 'Anymex', 'downloaded'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await Directory(p.join(dir.path, 'manga')).create(recursive: true);
    await Directory(p.join(dir.path, 'anime')).create(recursive: true);
    return dir;
  }

  String _downloadKey({
    required ItemType type,
    required String mediaId,
    required num number,
  }) => '${type.name}:$mediaId:$number';

  void _addActiveDownload(String key) {
    final set = _activeDownloads.value;
    if (set.add(key)) {
      _activeDownloads.refresh();
    }
  }

  void _removeActiveDownload(String key) {
    final set = _activeDownloads.value;
    if (set.remove(key)) {
      _activeDownloads.refresh();
    }
  }

  bool isChapterDownloading(String mediaId, double? chapterNumber) {
    if (chapterNumber == null) return false;
    return _activeDownloads.value
        .contains(_downloadKey(type: ItemType.manga, mediaId: mediaId, number: chapterNumber));
  }

  bool isEpisodeDownloading(String mediaId, String episodeNumber) {
    return _activeDownloads.value
        .contains(_downloadKey(type: ItemType.anime, mediaId: mediaId, number: _episodeKeyValue(episodeNumber)));
  }

  num _episodeKeyValue(String episodeNumber) {
    return double.tryParse(episodeNumber) ?? episodeNumber.hashCode;
  }

  Future<void> refreshChapterCache(String mediaId) async {
    _chapterCache[mediaId] = await getDownloadedChapters(mediaId);
    _chapterCache.refresh();
  }

  Future<void> refreshEpisodeCache(String mediaId) async {
    _episodeCache[mediaId] = await getDownloadedEpisodes(mediaId);
    _episodeCache.refresh();
  }

  DownloadedChapter? findDownloadedChapter(String mediaId, double? number) {
    if (number == null) return null;
    final entries = _chapterCache[mediaId] ?? [];
    return entries.firstWhereOrNull((e) => e.chapterNumber == number);
  }

  DownloadedEpisode? findDownloadedEpisode(String mediaId, String number) {
    final entries = _episodeCache[mediaId] ?? [];
    return entries.firstWhereOrNull((e) => e.episodeNumber == number) ??
        entries.firstWhereOrNull((e) => e.episodeNumber == number.padLeft(3, '0'));
  }

  List<Chapter> buildChapterModels(Media media) {
    final entries = _chapterCache[media.id] ?? [];
    return entries
        .map((entry) => Chapter(
              title: entry.title ?? 'Chapter ${entry.chapterNumber}',
              number: entry.chapterNumber,
              link: entry.directory.path,
              releaseDate: entry.directory.statSync().modified.toIso8601String(),
              sourceName: downloadedSourceLabel,
            ))
        .toList();
  }

  List<hive.Episode> buildEpisodeModels(Media media) {
    final entries = _episodeCache[media.id] ?? [];
    return entries
        .map((entry) => hive.Episode(
              number: entry.episodeNumber,
              title: entry.title ?? 'Episode ${entry.episodeNumber}',
              link: entry.filePath,
              source: downloadedSourceLabel,
            ))
        .toList();
  }

  String _slugify(String input) {
    final sanitized = input
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    return sanitized.isEmpty ? 'anymex' : sanitized.toLowerCase();
  }

  Future<Directory> _ensureChapterDir(Media media, Chapter chapter) async {
    final base = await _baseDirFuture;
    final slug = _slugify(media.title ?? media.romajiTitle ?? media.id);
    final chapterNumber = (chapter.number ?? 0).toInt().toString().padLeft(3, '0');
    final dir = Directory(p.join(base.path, 'manga', slug, 'c$chapterNumber'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _ensureEpisodeDir(Media media, hive.Episode episode) async {
    final base = await _baseDirFuture;
    final slug = _slugify(media.title ?? media.romajiTitle ?? media.id);
    final epNumber = episode.number.toString().padLeft(3, '0');
    final dir = Directory(p.join(base.path, 'anime', slug, 'e$epNumber'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> downloadChapter({
    required Media media,
    required Chapter chapter,
    Source? source,
  }) async {
    final chapterNumber = chapter.number ?? 0;
    final trackingKey =
        _downloadKey(type: ItemType.manga, mediaId: media.id, number: chapterNumber);
    _clearCancellationState(trackingKey);
    _addActiveDownload(trackingKey);
    _registerContext(
      trackingKey,
      DownloadProgressContext(
        type: ItemType.manga,
        mediaId: media.id,
        mediaTitle: media.title?.isNotEmpty == true
            ? media.title
            : media.romajiTitle,
        chapterNumber: chapterNumber.toDouble(),
        chapterTitle: chapter.title,
      ),
    );
    _updateProgress(trackingKey, 0.0);
    try {
      _throwIfCancelled(trackingKey);
      final link = chapter.link;
      if (link == null || link.isEmpty) {
        errorSnackBar('Missing chapter link for download.');
        return;
      }

      final controller = Get.find<SourceController>();
      final activeSource = source ?? controller.activeMangaSource.value;
      if (activeSource == null) {
        errorSnackBar('No manga source selected.');
        return;
      }

      _throwIfCancelled(trackingKey);

      final dir = await _ensureChapterDir(media, chapter);
      final metaFile = File(p.join(dir.path, 'meta.json'));
      if (await metaFile.exists()) {
        infoSnackBar('Chapter already downloaded.');
        return;
      }

      successSnackBar('Downloading chapter ${chapter.number?.toStringAsFixed(0) ?? ''}');
      final pageList = await activeSource.methods
          .getPageList(DEpisode(episodeNumber: '${chapter.number ?? '1'}', url: link));

      if (pageList.isEmpty) {
        errorSnackBar('No pages returned by source.');
        return;
      }

      _throwIfCancelled(trackingKey);

      final pageTasks = _buildChapterTasks(pageList, dir);
      final failedTasks = <_ChapterPageTask>[];
      _updateProgress(trackingKey, 0.0);

      for (final task in pageTasks) {
        _throwIfCancelled(trackingKey);
        final success = await _attemptPrimaryPageDownload(task, trackingKey);
        if (!success) {
          Logger.i('Queued page ${task.index + 1} for fallback capture.');
          failedTasks.add(task);
        }
      }

      if (failedTasks.isNotEmpty) {
        Logger.i('Detected ${failedTasks.length} failed page(s). Initiating fallback.');
        var pendingFailures = failedTasks;

        if (pendingFailures.length < _fullChapterCaptureThreshold) {
          pendingFailures = await _retryFailedPagesWithCache(
            pendingFailures,
            trackingKey,
          );
        }

        if (pendingFailures.isNotEmpty) {
          final captureSucceeded = await _performFullChapterCapture(
            tasks: pageTasks,
            trackingKey: trackingKey,
          );

          if (!captureSucceeded) {
            throw Exception(
                'Unable to capture ${pendingFailures.length} page(s) even after full-chapter fallback.');
          }

          pendingFailures = [];
        }
      }

      final fileNames = pageTasks.map((task) => task.fileName).toList();
      _updateProgress(trackingKey, 1.0);

      final metadata = {
        'type': 'manga',
        'mediaId': media.id,
        'title': media.title,
        'chapterNumber': chapter.number,
        'chapterTitle': chapter.title,
        'files': fileNames,
        'downloadedAt': DateTime.now().toIso8601String(),
        'source': activeSource.name,
        'link': link,
      };
      await metaFile.writeAsString(jsonEncode(metadata));
      successSnackBar('Chapter saved for offline reading.');
      await refreshChapterCache(media.id);
    } on DownloadCancelledException {
      infoSnackBar('Download canceled.');
    } catch (e, stackTrace) {
      errorSnackBar('Failed to download chapter: $e');
      Logger.i(stackTrace.toString());
    } finally {
      _clearProgress(trackingKey);
      _removeContext(trackingKey);
      _removeActiveDownload(trackingKey);
      _clearCancellationState(trackingKey);
    }
  }

  Future<void> _downloadImageWithStrategies(
    String url,
    File targetFile, {
    Map<String, String>? headers,
    required String cancelKey,
  }) async {
    int retries = 0;
    const maxRetries = 3;
    
    while (retries < maxRetries) {
      _throwIfCancelled(cancelKey);
      try {
        // Strategy 1: Direct Dio
        await _downloadBinary(
          url,
          targetFile,
          headers: headers,
          cancelKey: cancelKey,
        );
        return;
      } catch (e) {
        Logger.i('Strategy 1 (Dio) failed for $url: $e');
      }

      try {
        // Strategy 2: Dio with User-Agent
        final newHeaders = Map<String, String>.from(headers ?? {});
        if (!newHeaders.containsKey('User-Agent')) {
          newHeaders['User-Agent'] = _fallbackUserAgent;
        }
        await _downloadBinary(
          url,
          targetFile,
          headers: newHeaders,
          cancelKey: cancelKey,
        );
        return;
      } catch (e) {
        Logger.i('Strategy 2 (UA) failed for $url: $e');
      }

      try {
        // Strategy 3: temp cached capture
        final file = await getNetworkImageFile(
          url,
          headers: headers,
          cancelKey: cancelKey,
        );
        await file.copy(targetFile.path);
        return;
      } catch (e) {
        Logger.i('Strategy 3 (cache capture) failed for $url: $e');
      }

      retries++;
      if (retries < maxRetries) {
        _throwIfCancelled(cancelKey);
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    
    throw Exception('Failed to download image after $maxRetries attempts and multiple strategies');
  }

  Future<void> downloadEpisode({
    required Media media,
    required hive.Episode episode,
    Source? source,
    Video? selectedVideo,
  }) async {
    final trackingKey = _downloadKey(
      type: ItemType.anime,
      mediaId: media.id,
      number: _episodeKeyValue(episode.number),
    );
    _clearCancellationState(trackingKey);
    _addActiveDownload(trackingKey);
    _registerContext(
      trackingKey,
      DownloadProgressContext(
        type: ItemType.anime,
        mediaId: media.id,
        mediaTitle: media.title.isNotEmpty ? media.title : media.romajiTitle,
        episodeNumber: episode.number,
        episodeTitle: episode.title,
      ),
    );
    _updateProgress(trackingKey, 0.0);
    try {
      _throwIfCancelled(trackingKey);
      final link = episode.link;
      if (link == null || link.isEmpty) {
        errorSnackBar('Missing episode link.');
        return;
      }

      final controller = Get.find<SourceController>();
      final activeSource = source ?? controller.activeSource.value;
      if (activeSource == null) {
        errorSnackBar('No anime source selected.');
        return;
      }

      _throwIfCancelled(trackingKey);
      final dir = await _ensureEpisodeDir(media, episode);
      final metaFile = File(p.join(dir.path, 'meta.json'));
      if (await metaFile.exists()) {
        infoSnackBar('Episode already downloaded.');
        return;
      }

      successSnackBar('Preparing streams for episode ${episode.number}');
      Video selected;
      if (selectedVideo != null) {
        selected = selectedVideo;
      } else {
        final videos = await activeSource.methods
            .getVideoList(DEpisode(episodeNumber: episode.number, url: link));
        if (videos.isEmpty) {
          errorSnackBar('Source returned no streams.');
          return;
        }
        selected = _selectBestVideo(videos);
      }

      _throwIfCancelled(trackingKey);
      final extension = _inferExtension(selected.url, fallback: '.mp4');
      final target = File(p.join(dir.path, 'episode$extension'));

      if (_isM3u8(selected.url)) {
        await _downloadHlsPlaylist(
          selected.url,
          dir,
          headers: selected.headers,
          progressKey: trackingKey,
        );
      } else {
        await _downloadBinary(
          selected.url,
          target,
          headers: selected.headers,
          onProgress: (received, total) {
            if (total == -1) return;
            _updateProgress(trackingKey, received / total);
          },
          cancelKey: trackingKey,
        );
        _updateProgress(trackingKey, 1.0);
      }

      final subtitleEntries = <DownloadedSubtitle>[];

      final metadata = {
        'type': 'anime',
        'mediaId': media.id,
        'title': media.title,
        'episodeNumber': episode.number,
        'episodeTitle': episode.title,
        'file': target.existsSync() ? target.path : p.join(dir.path, 'playlist.m3u8'),
        'quality': selected.title ?? selected.quality ?? '',
        'downloadedAt': DateTime.now().toIso8601String(),
        'source': activeSource.name,
        'subtitles': subtitleEntries.map((entry) => entry.toJson()).toList(),
      };
      await metaFile.writeAsString(jsonEncode(metadata));
      successSnackBar('Episode saved for offline playback.');
      await refreshEpisodeCache(media.id);
    } on DownloadCancelledException {
      infoSnackBar('Download canceled.');
    } catch (e, stackTrace) {
      errorSnackBar('Failed to download episode: $e');
      Logger.i(stackTrace.toString());
    } finally {
      _clearProgress(trackingKey);
      _removeContext(trackingKey);
      _removeActiveDownload(trackingKey);
      _clearCancellationState(trackingKey);
    }
  }

  Future<List<DownloadedChapter>> getDownloadedChapters(String mediaId) async {
    final entries = await _collectDownloadedChapters(filterMediaId: mediaId);
    entries.sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
    return entries;
  }

  Future<List<DownloadedChapter>> listAllDownloadedChapters() async {
    final entries = await _collectDownloadedChapters();
    entries.sort((a, b) {
      final titleCompare = (a.mediaTitle ?? '').compareTo(b.mediaTitle ?? '');
      if (titleCompare != 0) return titleCompare;
      return a.chapterNumber.compareTo(b.chapterNumber);
    });
    return entries;
  }

  Future<List<DownloadedEpisode>> getDownloadedEpisodes(String mediaId) async {
    final entries = await _collectDownloadedEpisodes(filterMediaId: mediaId);
    entries.sort((a, b) => _episodeSortValue(a.episodeNumber)
        .compareTo(_episodeSortValue(b.episodeNumber)));
    return entries;
  }

  Future<List<DownloadedEpisode>> listAllDownloadedEpisodes() async {
    final entries = await _collectDownloadedEpisodes();
    entries.sort((a, b) {
      final titleCompare = (a.mediaTitle ?? '').compareTo(b.mediaTitle ?? '');
      if (titleCompare != 0) return titleCompare;
      return _episodeSortValue(a.episodeNumber)
          .compareTo(_episodeSortValue(b.episodeNumber));
    });
    return entries;
  }

  Future<List<DownloadedChapter>> _collectDownloadedChapters({String? filterMediaId}) async {
    final base = await _baseDirFuture;
    final mangaDir = Directory(p.join(base.path, 'manga'));
    if (!await mangaDir.exists()) return [];

    final results = <DownloadedChapter>[];
    final directories = mangaDir
        .listSync(recursive: true)
        .whereType<Directory>()
        .where((dir) => File(p.join(dir.path, 'meta.json')).existsSync());

    for (final dir in directories) {
      try {
        final metaFile = File(p.join(dir.path, 'meta.json'));
        final meta = jsonDecode(await metaFile.readAsString());
        if (meta['type'] != 'manga') continue;
        final mediaId = meta['mediaId']?.toString() ?? '';
        if (mediaId.isEmpty) continue;
        if (filterMediaId != null && mediaId != filterMediaId) continue;
        results.add(
          DownloadedChapter(
            directory: dir,
            mediaId: mediaId,
            mediaTitle: meta['title']?.toString(),
            chapterNumber: (meta['chapterNumber'] as num?)?.toDouble() ?? 0,
            title: meta['chapterTitle']?.toString(),
            files: (meta['files'] as List<dynamic>? ?? const <dynamic>[])
                .map((e) => e.toString())
                .toList(),
            sizeBytes: _calculateDirectorySize(dir),
          ),
        );
      } catch (_) {
        continue;
      }
    }

    return results;
  }

  Future<List<DownloadedEpisode>> _collectDownloadedEpisodes({String? filterMediaId}) async {
    final base = await _baseDirFuture;
    final animeDir = Directory(p.join(base.path, 'anime'));
    if (!await animeDir.exists()) return [];

    final results = <DownloadedEpisode>[];
    final directories = animeDir
        .listSync(recursive: true)
        .whereType<Directory>()
        .where((dir) => File(p.join(dir.path, 'meta.json')).existsSync());

    for (final dir in directories) {
      try {
        final metaFile = File(p.join(dir.path, 'meta.json'));
        final meta = jsonDecode(await metaFile.readAsString());
        if (meta['type'] != 'anime') continue;
        final mediaId = meta['mediaId']?.toString() ?? '';
        if (mediaId.isEmpty) continue;
        if (filterMediaId != null && mediaId != filterMediaId) continue;
        final subtitles = (meta['subtitles'] as List<dynamic>? ?? const [])
            .map((entry) {
              if (entry is Map<String, dynamic>) {
                return DownloadedSubtitle.fromJson(entry);
              }
              if (entry is Map) {
                return DownloadedSubtitle.fromJson(
                    entry.map((key, value) => MapEntry(key.toString(), value)));
              }
              return null;
            })
            .whereType<DownloadedSubtitle>()
            .toList();
        results.add(DownloadedEpisode(
          directory: dir,
          mediaId: mediaId,
          mediaTitle: meta['title']?.toString(),
          filePath: meta['file']?.toString(),
          episodeNumber: meta['episodeNumber']?.toString() ?? '0',
          title: meta['episodeTitle']?.toString(),
          subtitles: subtitles,
          sizeBytes: _calculateDirectorySize(dir),
        ));
      } catch (_) {
        continue;
      }
    }

    return results;
  }

  int _episodeSortValue(String number) {
    final cleaned = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return 0;
    return int.tryParse(cleaned) ?? 0;
  }

  int _calculateDirectorySize(Directory dir) {
    var total = 0;
    for (final entity
        in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += entity.lengthSync();
      }
    }
    return total;
  }

  Future<void> deleteDownloadedEpisode(DownloadedEpisode episode) async {
    try {
      if (await episode.directory.exists()) {
        await episode.directory.delete(recursive: true);
      }
    } catch (e) {
      Logger.i('Failed to delete episode download: $e');
    } finally {
      await refreshEpisodeCache(episode.mediaId);
    }
  }

  Future<void> deleteDownloadedChapter(DownloadedChapter chapter) async {
    try {
      if (await chapter.directory.exists()) {
        await chapter.directory.delete(recursive: true);
      }
    } catch (e) {
      Logger.i('Failed to delete chapter download: $e');
    } finally {
      await refreshChapterCache(chapter.mediaId);
    }
  }

  List<_ChapterPageTask> _buildChapterTasks(
      List<PageUrl> pageList, Directory targetDir) {
    return List.generate(pageList.length, (index) {
      final page = pageList[index];
      final ext = _inferExtension(page.url);
      final fileName = '${(index + 1).toString().padLeft(3, '0')}$ext';
      final file = File(p.join(targetDir.path, fileName));
      return _ChapterPageTask(
        page: page,
        targetFile: file,
        index: index,
        totalPages: pageList.length,
        fileName: fileName,
      );
    });
  }

  Future<bool> _attemptPrimaryPageDownload(
      _ChapterPageTask task, String trackingKey) async {
    try {
      _throwIfCancelled(trackingKey);
      await _downloadImageWithStrategies(
        task.page.url,
        task.targetFile,
        headers: task.page.headers,
        cancelKey: trackingKey,
      );
      return true;
    } catch (e, stackTrace) {
      Logger.i('Primary download failed for page ${task.index + 1}: $e');
      Logger.i(stackTrace.toString());
      return false;
    } finally {
      _updateProgress(trackingKey, (task.index + 1) / task.totalPages);
    }
  }

  Future<List<_ChapterPageTask>> _retryFailedPagesWithCache(
      List<_ChapterPageTask> failedPages, String trackingKey) async {
    if (failedPages.isEmpty) return failedPages;
    infoSnackBar('Retrying failed pages with cached capture…');
    final stillFailed = <_ChapterPageTask>[];

    for (final task in failedPages) {
      _throwIfCancelled(trackingKey);
      try {
        final bustedUrl = _appendCacheBuster(task.page.url);
        final file = await getNetworkImageFile(
          bustedUrl,
          headers: _buildFallbackHeaders(task.page.headers),
          cancelKey: trackingKey,
        );
        await file.copy(task.targetFile.path);
      } catch (e, stackTrace) {
        Logger.i('Cache fallback failed for page ${task.index + 1}: $e');
        Logger.i(stackTrace.toString());
        stillFailed.add(task);
      } finally {
        _updateProgress(trackingKey, (task.index + 1) / task.totalPages);
      }
    }

    return stillFailed;
  }

  Future<bool> _performFullChapterCapture({
    required List<_ChapterPageTask> tasks,
    required String trackingKey,
  }) async {
    if (tasks.isEmpty) {
      return true;
    }

    infoSnackBar('Falling back to full chapter capture…');
    for (final task in tasks) {
      _throwIfCancelled(trackingKey);
      try {
        final bustedUrl = _appendCacheBuster(task.page.url);
        final file = await getNetworkImageFile(
          bustedUrl,
          headers: _buildFallbackHeaders(task.page.headers),
          cancelKey: trackingKey,
        );
        await file.copy(task.targetFile.path);
      } catch (e, stackTrace) {
        Logger.i('Full chapter capture failed at page ${task.index + 1}: $e');
        Logger.i(stackTrace.toString());
        return false;
      } finally {
        _updateProgress(trackingKey, (task.index + 1) / task.totalPages);
      }
    }

    return true;
  }

  Map<String, String> _buildFallbackHeaders(Map<String, String>? base) {
    final headers = Map<String, String>.from(base ?? {});
    headers['User-Agent'] ??= _fallbackUserAgent;
    headers['Cache-Control'] = 'no-cache';
    headers['Pragma'] = 'no-cache';
    return headers;
  }

  String _appendCacheBuster(String url) {
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}cb=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _downloadBinary(String url, File file,
      {Map<String, String>? headers,
      void Function(int received, int total)? onProgress,
      String? cancelKey}) async {
    CancelToken? cancelToken;
    if (cancelKey != null) {
      _throwIfCancelled(cancelKey);
      cancelToken = CancelToken();
      _registerCancelToken(cancelKey, cancelToken);
    }

    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          headers: headers,
        ),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          onProgress?.call(received, total);
        },
      );
      await file.writeAsBytes(response.data!);
    } on DioException catch (e) {
      if (cancelKey != null &&
          (cancelToken?.isCancelled == true ||
              e.type == DioExceptionType.cancel)) {
        throw DownloadCancelledException(cancelKey);
      }
      rethrow;
    } finally {
      if (cancelKey != null && cancelToken != null) {
        _releaseCancelToken(cancelKey, cancelToken);
      }
    }
  }

  Future<File> getNetworkImageFile(
    String url, {
    Map<String, String>? headers,
    String? cancelKey,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(tempDir.path, 'anymex_image_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final safeHash = (url.hashCode & 0x7fffffff).toString();
    final extension = _inferExtension(url, fallback: '.img');
    final file = File(p.join(cacheDir.path, 'img_$safeHash$extension'));

    if (await file.exists()) {
      final length = await file.length();
      if (length > 0) {
        return file;
      }
      await file.delete();
    }

    final tempFile = File('${file.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    try {
      await _downloadBinary(
        url,
        tempFile,
        headers: headers,
        cancelKey: cancelKey,
      );
      await tempFile.rename(file.path);
      return file;
    } catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }


  Future<void> _downloadHlsPlaylist(String playlistUrl, Directory targetDir,
      {Map<String, String>? headers, String? progressKey}) async {
    final playlistContent = await _fetchPlaylist(
      playlistUrl,
      headers: headers,
      cancelKey: progressKey,
    );
    final lines = LineSplitter.split(playlistContent).toList();
    final totalSegments =
        lines.where((line) => !_isCommentOrEmpty(line)).length;
    final buffer = StringBuffer();
    var completedSegments = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (_isCommentOrEmpty(trimmed)) {
        buffer.writeln(trimmed);
        continue;
      }

      if (progressKey != null) {
        _throwIfCancelled(progressKey);
      }
      final absolute = _resolveUrl(playlistUrl, trimmed);
      final ext = _inferExtension(absolute, fallback: '.ts');
      final segmentName =
          'segment_${completedSegments.toString().padLeft(4, '0')}$ext';
      final file = File(p.join(targetDir.path, segmentName));
      await _downloadBinary(
        absolute,
        file,
        headers: headers,
        onProgress: (received, total) {
          if (progressKey == null || total == -1 || totalSegments == 0) return;
          final segmentFraction = (received / total).clamp(0, 1);
          _updateProgress(
              progressKey, (completedSegments + segmentFraction) / totalSegments);
        },
        cancelKey: progressKey,
      );
      completedSegments++;
      if (progressKey != null && totalSegments > 0) {
        _updateProgress(progressKey, completedSegments / totalSegments);
      }
      buffer.writeln(segmentName);
    }

    if (progressKey != null) {
      _updateProgress(progressKey, 1.0);
    }

    final playlistFile = File(p.join(targetDir.path, 'playlist.m3u8'));
    await playlistFile.writeAsString(buffer.toString());
  }

  bool _isCommentOrEmpty(String line) {
    return line.isEmpty || line.startsWith('#');
  }

  Future<String> _fetchPlaylist(String url,
      {Map<String, String>? headers, String? cancelKey}) async {
    CancelToken? cancelToken;
    if (cancelKey != null) {
      _throwIfCancelled(cancelKey);
      cancelToken = CancelToken();
      _registerCancelToken(cancelKey, cancelToken);
    }

    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
        ),
        cancelToken: cancelToken,
      );
      final data = response.data ?? '';
      if (data.contains('#EXT-X-STREAM-INF')) {
        final selectedUrl = _selectVariantPlaylist(data, url);
        if (selectedUrl != null && selectedUrl != url) {
          return _fetchPlaylist(
            selectedUrl,
            headers: headers,
            cancelKey: cancelKey,
          );
        }
      }
      return data;
    } on DioException catch (e) {
      if (cancelKey != null &&
          (cancelToken?.isCancelled == true ||
              e.type == DioExceptionType.cancel)) {
        throw DownloadCancelledException(cancelKey);
      }
      rethrow;
    } finally {
      if (cancelKey != null && cancelToken != null) {
        _releaseCancelToken(cancelKey, cancelToken);
      }
    }
  }

  String? _selectVariantPlaylist(String playlist, String baseUrl) {
    final lines = playlist.split('\n');
    final variants = <_VariantPlaylist>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        final bandwidth = int.tryParse(bandwidthMatch?.group(1) ?? '0') ?? 0;
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
            variants.add(_VariantPlaylist(
              url: _resolveUrl(baseUrl, nextLine),
              bandwidth: bandwidth,
            ));
          }
        }
      }
    }
    if (variants.isEmpty) return null;
    variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    return variants.first.url;
  }

  String _resolveUrl(String baseUrl, String relativePath) {
    final baseUri = Uri.parse(baseUrl);
    final resolved = baseUri.resolve(relativePath);
    return resolved.toString();
  }

  String _inferExtension(String url, {String fallback = '.jpg'}) {
    final uri = Uri.parse(url.split('?').first);
    final ext = p.extension(uri.path);
    if (ext.isNotEmpty) return ext;
    return fallback;
  }

  bool _isM3u8(String url) => url.toLowerCase().contains('.m3u8');

  Video _selectBestVideo(List<Video> videos) {
    videos.sort((a, b) =>
        _qualityScore(b.quality ?? b.title ?? '') - _qualityScore(a.quality ?? a.title ?? ''));
    return videos.first;
  }

  int _qualityScore(String quality) {
    if (quality.contains('2160')) return 5;
    if (quality.contains('1440')) return 4;
    if (quality.contains('1080')) return 3;
    if (quality.contains('720')) return 2;
    if (quality.contains('480')) return 1;
    return 0;
  }
}

class DownloadedChapter {
  final Directory directory;
  final String mediaId;
  final String? mediaTitle;
  final double chapterNumber;
  final String? title;
  final List<String> files;
  final int sizeBytes;

  DownloadedChapter({
    required this.directory,
    required this.mediaId,
    required this.mediaTitle,
    required this.chapterNumber,
    required this.title,
    required this.files,
    required this.sizeBytes,
  });
}

class DownloadedEpisode {
  final Directory directory;
  final String mediaId;
  final String? mediaTitle;
  final String? filePath;
  final String episodeNumber;
  final String? title;
  final List<DownloadedSubtitle> subtitles;
  final int sizeBytes;

  DownloadedEpisode({
    required this.directory,
    required this.mediaId,
    required this.mediaTitle,
    required this.filePath,
    required this.episodeNumber,
    required this.title,
    this.subtitles = const [],
    required this.sizeBytes,
  });
}

class DownloadedSubtitle {
  final String path;
  final String label;
  final String? languageCode;

  const DownloadedSubtitle({
    required this.path,
    required this.label,
    this.languageCode,
  });

  factory DownloadedSubtitle.fromJson(Map<String, dynamic> json) {
    return DownloadedSubtitle(
      path: json['path']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      languageCode: json['languageCode']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'label': label,
        if (languageCode != null && languageCode!.isNotEmpty)
          'languageCode': languageCode,
      };

  String get displayLabel =>
    label.isNotEmpty ? label : (languageCode?.toUpperCase() ?? 'SUBTITLE');
}

class _ChapterPageTask {
  _ChapterPageTask({
    required this.page,
    required this.targetFile,
    required this.index,
    required this.totalPages,
    required this.fileName,
  });

  final PageUrl page;
  final File targetFile;
  final int index;
  final int totalPages;
  final String fileName;
}

class DownloadProgressContext {
  const DownloadProgressContext({
    required this.type,
    required this.mediaId,
    required this.mediaTitle,
    this.episodeNumber,
    this.episodeTitle,
    this.chapterNumber,
    this.chapterTitle,
  });

  final ItemType type;
  final String mediaId;
  final String? mediaTitle;
  final String? episodeNumber;
  final String? episodeTitle;
  final double? chapterNumber;
  final String? chapterTitle;
}

class _VariantPlaylist {
  final String url;
  final int bandwidth;

  _VariantPlaylist({required this.url, required this.bandwidth});
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException(this.key);
  final String key;

  @override
  String toString() => 'Download cancelled: $key';
}
