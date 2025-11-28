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
  Map<String, double> get progress => _progress;

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
    _addActiveDownload(trackingKey);
    try {
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

      final fileNames = <String>[];
      for (var i = 0; i < pageList.length; i++) {
        final page = pageList[i];
        final ext = _inferExtension(page.url);
        final fileName = '${(i + 1).toString().padLeft(3, '0')}$ext';
        final file = File(p.join(dir.path, fileName));
        await _downloadBinary(page.url, file, headers: page.headers);
        fileNames.add(fileName);
      }

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
    } catch (e, stackTrace) {
      errorSnackBar('Failed to download chapter: $e');
      Logger.i(stackTrace.toString());
    } finally {
      _removeActiveDownload(trackingKey);
    }
  }

  Future<void> downloadEpisode({
    required Media media,
    required hive.Episode episode,
    Source? source,
  }) async {
    final trackingKey = _downloadKey(
      type: ItemType.anime,
      mediaId: media.id,
      number: _episodeKeyValue(episode.number),
    );
    _addActiveDownload(trackingKey);
    try {
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

      final dir = await _ensureEpisodeDir(media, episode);
      final metaFile = File(p.join(dir.path, 'meta.json'));
      if (await metaFile.exists()) {
        infoSnackBar('Episode already downloaded.');
        return;
      }

      successSnackBar('Fetching streams for episode ${episode.number}');
      final videos = await activeSource.methods
          .getVideoList(DEpisode(episodeNumber: episode.number, url: link));
      if (videos.isEmpty) {
        errorSnackBar('Source returned no streams.');
        return;
      }

      final selected = _selectBestVideo(videos);
      final extension = _inferExtension(selected.url, fallback: '.mp4');
      final target = File(p.join(dir.path, 'episode$extension'));

      if (_isM3u8(selected.url)) {
        await _downloadHlsPlaylist(selected.url, dir, headers: selected.headers);
      } else {
        await _downloadBinary(selected.url, target, headers: selected.headers);
      }

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
      };
      await metaFile.writeAsString(jsonEncode(metadata));
      successSnackBar('Episode saved for offline playback.');
      await refreshEpisodeCache(media.id);
    } catch (e, stackTrace) {
      errorSnackBar('Failed to download episode: $e');
      Logger.i(stackTrace.toString());
    } finally {
      _removeActiveDownload(trackingKey);
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
        results.add(DownloadedEpisode(
          directory: dir,
          mediaId: mediaId,
          mediaTitle: meta['title']?.toString(),
          filePath: meta['file']?.toString(),
          episodeNumber: meta['episodeNumber']?.toString() ?? '0',
          title: meta['episodeTitle']?.toString(),
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

  Future<void> _downloadBinary(String url, File file,
      {Map<String, String>? headers}) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        headers: headers,
      ),
      onReceiveProgress: (received, total) {
        if (total != -1) {
          _progress[file.path] = received / total;
        }
      },
    );
    await file.writeAsBytes(response.data!);
    _progress.remove(file.path);
  }

  Future<void> _downloadHlsPlaylist(String playlistUrl, Directory targetDir,
      {Map<String, String>? headers}) async {
    final playlistContent = await _fetchPlaylist(playlistUrl, headers: headers);
    final segments = <String>[];
    final buffer = StringBuffer();

    for (final line in LineSplitter.split(playlistContent)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#') || trimmed.isEmpty) {
        buffer.writeln(trimmed);
        continue;
      }

      final absolute = _resolveUrl(playlistUrl, trimmed);
      final ext = _inferExtension(absolute, fallback: '.ts');
      final segmentName = 'segment_${segments.length.toString().padLeft(4, '0')}$ext';
      final file = File(p.join(targetDir.path, segmentName));
      await _downloadBinary(absolute, file, headers: headers);
      buffer.writeln(segmentName);
      segments.add(segmentName);
    }

    final playlistFile = File(p.join(targetDir.path, 'playlist.m3u8'));
    await playlistFile.writeAsString(buffer.toString());
  }

  Future<String> _fetchPlaylist(String url, {Map<String, String>? headers}) async {
    final response = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: headers,
      ),
    );
    final data = response.data ?? '';
    if (data.contains('#EXT-X-STREAM-INF')) {
      final selectedUrl = _selectVariantPlaylist(data, url);
      if (selectedUrl != null && selectedUrl != url) {
        return _fetchPlaylist(selectedUrl, headers: headers);
      }
    }
    return data;
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
  final int sizeBytes;

  DownloadedEpisode({
    required this.directory,
    required this.mediaId,
    required this.mediaTitle,
    required this.filePath,
    required this.episodeNumber,
    required this.title,
    required this.sizeBytes,
  });
}

class _VariantPlaylist {
  final String url;
  final int bandwidth;

  _VariantPlaylist({required this.url, required this.bandwidth});
}
