// ignore_for_file: invalid_use_of_protected_member, prefer_const_constructors, unnecessary_null_comparison
import 'dart:async';
import 'dart:io';
import 'package:anymex/controllers/download/download_controller.dart';
import 'package:anymex/controllers/service_handler/service_handler.dart';
import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/database/data_keys/general.dart';
import 'package:anymex/models/Offline/Hive/video.dart' as hive;
import 'package:anymex/controllers/offline/offline_storage_controller.dart';
import 'package:anymex/controllers/source/source_controller.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:anymex/models/Offline/Hive/episode.dart';
import 'package:anymex/screens/anime/watch/watch_view.dart';
import 'package:anymex/screens/anime/watch_page.dart';
import 'package:anymex/screens/local_source/player/offline_player.dart';
import 'package:anymex/screens/local_source/player/offline_player_old.dart';
import 'package:anymex/screens/anime/widgets/episode/normal_episode.dart';
import 'package:anymex/screens/anime/widgets/episode_range.dart';
import 'package:anymex/screens/anime/widgets/track_dialog.dart';
import 'package:anymex/utils/function.dart';
import 'package:anymex/utils/string_extensions.dart';
import 'package:anymex/widgets/custom_widgets/anymex_button.dart';
import 'package:anymex/widgets/custom_widgets/anymex_chip.dart';
import 'package:anymex/widgets/common/hold_to_cancel_detector.dart';
import 'package:anymex/widgets/header.dart';
import 'package:anymex/widgets/helper/platform_builder.dart';
import 'package:anymex/widgets/custom_widgets/custom_text.dart';
import 'package:anymex/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class EpisodeListBuilder extends StatefulWidget {
  const EpisodeListBuilder({
    super.key,
    required this.episodeList,
    required this.anilistData,
    this.showingDownloaded = false,
    this.downloadedEntries = const <DownloadedEpisode>[],
  });

  final List<Episode> episodeList;
  final Media? anilistData;
  final bool showingDownloaded;
  final List<DownloadedEpisode> downloadedEntries;

  @override
  State<EpisodeListBuilder> createState() => _EpisodeListBuilderState();
}

class _BlockingProgressDialog extends StatelessWidget {
  const _BlockingProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeListBuilderState extends State<EpisodeListBuilder> {
  final selectedChunkIndex = 1.obs;
  final RxList<hive.Video> streamList = <hive.Video>[].obs;
  final sourceController = Get.find<SourceController>();
  final auth = Get.find<ServiceHandler>();
  final offlineStorage = Get.find<OfflineStorageController>();
  late final DownloadController _downloadController;

  final RxBool isLogged = false.obs;
  final RxInt userProgress = 0.obs;
  final Rx<Episode> selectedEpisode = Episode(number: "1").obs;
  final Rx<Episode> continueEpisode = Episode(number: "1").obs;
  final Rx<Episode> savedEpisode = Episode(number: "1").obs;
  List<Episode> offlineEpisodes = [];

  @override
  void initState() {
    super.initState();
    _downloadController = Get.find<DownloadController>();
    _initEpisodes();
    Future.delayed(Duration(milliseconds: 300), () {
      _initUserProgress();
    });
    _initEpisodes();

    ever(auth.isLoggedIn, (_) => _initUserProgress());
    ever(userProgress, (_) => _initEpisodes());
    ever(auth.currentMedia, (_) => {_initUserProgress(), _initEpisodes()});

    offlineStorage.addListener(() {
      final savedData = offlineStorage.getAnimeById(widget.anilistData!.id);
      if (savedData?.currentEpisode != null) {
        savedEpisode.value = savedData!.currentEpisode!;
        offlineEpisodes = savedData.episodes ?? [];
        _initEpisodes();
      }
    });
  }

  void _initUserProgress() {
    final isExtensions = auth.serviceType.value == ServicesType.extensions;
    isLogged.value = isExtensions ? false : auth.isLoggedIn.value;
    final progress = isLogged.value
        ? auth.currentMedia.value.episodeCount?.toInt()
        : offlineStorage
            .getAnimeById(widget.anilistData!.id)
            ?.currentEpisode
            ?.number
            .toInt();

    userProgress.value = !isLogged.value && progress != null && progress > 1
        ? progress - 1
        : progress ?? 0;
  }

  void _initEpisodes() {
    final savedData = offlineStorage.getAnimeById(widget.anilistData!.id);
    final nextEpisode = widget.episodeList
        .firstWhereOrNull((e) => e.number.toInt() == (userProgress.value + 1));
    final fallbackEP = widget.episodeList
        .firstWhereOrNull((e) => e.number.toInt() == (userProgress.value));
    final saved = savedData?.currentEpisode;
    savedEpisode.value = saved ?? widget.episodeList[0];
    offlineEpisodes = savedData?.watchedEpisodes ?? widget.episodeList;
    selectedEpisode.value = nextEpisode ?? fallbackEP ?? savedEpisode.value;
    continueEpisode.value = nextEpisode ?? fallbackEP ?? savedEpisode.value;
  }

  String _normalizeEpisodeKey(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null) {
      return parsed.toString();
    }
    return value.trim();
  }

  void _handleEpisodeSelection(Episode episode) async {
    selectedEpisode.value = episode;
    streamList.clear();
    fetchServers(episode);
  }

  Widget _buildContinueButton() {
    return ContinueEpisodeButton(
      height: getResponsiveSize(context, mobileSize: 80, desktopSize: 100),
      onPressed: () {
        if (widget.showingDownloaded) {
          _openDownloadedEpisode(continueEpisode.value);
        } else {
          _handleEpisodeSelection(continueEpisode.value);
        }
      },
      backgroundImage: continueEpisode.value.thumbnail ??
          savedEpisode.value.thumbnail ??
          widget.anilistData!.cover ??
          widget.anilistData!.poster,
      episode: continueEpisode.value,
      progressEpisode: savedEpisode.value,
      data: widget.anilistData!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chunkedEpisodes = chunkEpisodes(
        widget.episodeList, calculateChunkSize(widget.episodeList));

    final isAnify = (widget.episodeList[0].thumbnail?.isNotEmpty ?? false).obs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          child: Obx(_buildContinueButton),
        ),
        EpisodeChunkSelector(
          chunks: chunkedEpisodes,
          selectedChunkIndex: selectedChunkIndex,
          onChunkSelected: (index) => setState(() {}),
        ),
        Obx(() {
          final selectedEpisodes = chunkedEpisodes.isNotEmpty
              ? chunkedEpisodes[selectedChunkIndex.value]
              : [];
          final downloadedMap = {
            for (final entry in widget.downloadedEntries)
              _normalizeEpisodeKey(entry.episodeNumber): entry
          };

          return GridView.builder(
            padding: const EdgeInsets.only(top: 15),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: getResponsiveCrossAxisCount(
                context,
                baseColumns: 1,
                maxColumns: 3,
                mobileItemWidth: 400,
                tabletItemWidth: 400,
                desktopItemWidth: 200,
              ),
              mainAxisSpacing:
                  getResponsiveSize(context, mobileSize: 15, desktopSize: 10),
              crossAxisSpacing: 15,
              mainAxisExtent: isAnify.value
                  ? 200
                  : getResponsiveSize(context,
                      mobileSize: 100, desktopSize: 130),
            ),
            itemCount: selectedEpisodes.length,
            itemBuilder: (context, index) {
              final episode = selectedEpisodes[index] as Episode;
              return Obx(() {
                final currentEpisode =
                    episode.number.toInt() + 1 == userProgress.value;
                final completedEpisode =
                    episode.number.toInt() <= userProgress.value;
                final isSelected =
                    selectedEpisode.value.number == episode.number;
        final downloadEntry =
          downloadedMap[_normalizeEpisodeKey(episode.number)];
        final isDownloaded = downloadEntry != null;
        final isDownloading = widget.anilistData != null &&
          _downloadController.isEpisodeDownloading(
            widget.anilistData!.id, episode.number);
        final downloadProgress = (isDownloading && widget.anilistData != null)
            ? _downloadController.getEpisodeProgress(
                widget.anilistData!.id, episode.number)
            : null;

                return Opacity(
                  opacity: completedEpisode
                      ? 0.5
                      : currentEpisode
                          ? 0.8
                          : 1,
                  child: Stack(
                    children: [
                      BetterEpisode(
                        episode: episode,
                        isSelected: isSelected,
                        layoutType: isAnify.value
                            ? EpisodeLayoutType.detailed
                            : EpisodeLayoutType.compact,
                        fallbackImageUrl:
                            episode.thumbnail ?? widget.anilistData!.poster,
                        offlineEpisodes: offlineEpisodes,
                        onTap: () {
                          if (widget.showingDownloaded && isDownloaded) {
                            _openDownloadedEpisode(episode, downloadEntry);
                          } else {
                            _handleEpisodeSelection(episode);
                          }
                        },
                      ),
                      if (!widget.showingDownloaded &&
                          widget.anilistData != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _buildDownloadBadge(
                            context,
                            isDownloaded: isDownloaded,
                            isDownloading: isDownloading,
                            progress: downloadProgress,
                            onTap: isDownloaded
                                ? () =>
                                    _openDownloadedEpisode(episode, downloadEntry)
                                : () => _downloadEpisode(episode),
                            onCancel: widget.anilistData == null
                                ? null
                                : () async {
                                    await _downloadController
                                        .cancelEpisodeDownload(
                                      widget.anilistData!.id,
                                      episode.number,
                                    );
                                  },
                          ),
                        ),
                    ],
                  ),
                );
              });
            },
          );
        }),
      ],
    );
  }

  Future<void> _downloadEpisode(Episode episode) async {
    if (widget.anilistData == null) return;
    final videos = await _loadDownloadServers(episode);
    if (!mounted || videos.isEmpty) return;

    if (videos.length == 1) {
      final label = _serverPrimaryLabel(videos.first, 0);
      infoSnackBar('Downloading from $label');
      await _startEpisodeDownload(episode, videos.first);
      return;
    }

    await _showDownloadServerSheet(episode, videos);
  }

  Future<List<Video>> _loadDownloadServers(Episode episode) async {
    if (!mounted) return [];
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BlockingProgressDialog(
        message: 'Fetching available servers…',
      ),
    );
    try {
      final link = episode.link;
      if (link == null || link.isEmpty) {
        errorSnackBar('Episode link missing for downloads.');
        return [];
      }

      final activeSource = sourceController.activeSource.value;
      if (activeSource == null) {
        errorSnackBar('Select a source before downloading this episode.');
        return [];
      }

      final videos = await activeSource.methods
          .getVideoList(DEpisode(episodeNumber: episode.number, url: link));
      if (videos.isEmpty) {
        errorSnackBar('Source returned no downloadable streams.');
      }
      return videos;
    } catch (e) {
      errorSnackBar('Failed to fetch download servers: $e');
      return [];
    } finally {
      if (navigator.mounted) {
        navigator.pop();
      }
    }
  }

  Future<void> _showDownloadServerSheet(
      Episode episode, List<Video> videos) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Text(
                  'Choose a server',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick the stream you want to download. Higher bitrates take longer and use more space.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: videos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final video = videos[index];
                      final primary = _serverPrimaryLabel(video, index);
                      final secondary = _serverSecondaryLabel(video);
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          child: Text(
                            '${index + 1}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(primary),
                        subtitle: secondary != null
                            ? Text(
                                secondary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: const Icon(Icons.download_rounded),
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          infoSnackBar('Downloading from $primary');
                          await _startEpisodeDownload(episode, video);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startEpisodeDownload(Episode episode, Video video) async {
    await _downloadController.downloadEpisode(
      media: widget.anilistData!,
      episode: episode,
      selectedVideo: video,
    );
  }

  String _serverPrimaryLabel(Video video, int index) {
    final title = video.title?.trim();
    final quality = video.quality?.trim();
    if (title?.isNotEmpty == true && quality?.isNotEmpty == true) {
      return '$title · $quality';
    }
    if (quality?.isNotEmpty == true) {
      return quality!;
    }
    if (title?.isNotEmpty == true) {
      return title!;
    }
    return 'Server ${index + 1}';
  }

  String? _serverSecondaryLabel(Video video) {
    final host = Uri.tryParse(video.url)?.host;
    return host?.isNotEmpty == true ? host : null;
  }

  Widget _buildDownloadBadge(BuildContext context,
      {required bool isDownloaded,
      required bool isDownloading,
      double? progress,
      required VoidCallback onTap,
      Future<void> Function()? onCancel}) {
    if (isDownloading) {
      final percent = progress != null ? (progress * 100).clamp(0, 100) : null;
      return HoldToCancelDetector(
        tooltip: 'Hold 2s to cancel download',
        onConfirmed: () async {
          if (onCancel != null) {
            await onCancel();
          }
        },
        overlayRadius: BorderRadius.circular(9999),
        progressColor: Theme.of(context).colorScheme.error,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Theme.of(context).colorScheme.primary,
                  value: progress,
                ),
              ),
              if (percent != null)
                Text(
                  '${percent.toStringAsFixed(percent >= 10 ? 0 : 1)}%',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
      );
    }

    return Tooltip(
      message: isDownloaded ? 'Open download' : 'Download episode',
      child: Material(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              isDownloaded ? Icons.check_circle : Icons.download_rounded,
              size: 18,
              color: isDownloaded
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  void _openDownloadedEpisode(Episode episode,
      [DownloadedEpisode? cachedEntry]) {
    if (widget.anilistData == null) {
      errorSnackBar('Missing media information for playback.');
      return;
    }
    final downloadEntry = cachedEntry ??
        _downloadController.findDownloadedEpisode(
          widget.anilistData!.id,
          episode.number,
        );
    final filePath = downloadEntry?.filePath ?? episode.link;
    if (filePath == null || filePath.isEmpty) {
      errorSnackBar('Offline file path missing for episode ${episode.number}.');
      return;
    }
    final file = File(filePath);
    if (!file.existsSync()) {
      errorSnackBar('Downloaded file is missing on disk.');
      return;
    }

  final subtitleTracksRaw = (downloadEntry?.subtitles ?? [])
    .where((subtitle) =>
      subtitle.path.isNotEmpty && File(subtitle.path).existsSync())
    .map((subtitle) => hive.Track(
        file: Uri.file(subtitle.path).toString(),
        label: subtitle.displayLabel,
      ))
    .toList();
  final subtitleTracks =
    subtitleTracksRaw.isEmpty ? null : subtitleTracksRaw;

    String _firstNonEmpty(List<String?> values, String fallback) {
      for (final value in values) {
        if (value != null && value.trim().isNotEmpty && value != '?') {
          return value;
        }
      }
      return fallback;
    }

    final folderName = _firstNonEmpty(
        [
          widget.anilistData?.title,
          widget.anilistData?.romajiTitle,
          downloadEntry?.mediaTitle,
        ],
        'Downloads');

    final episodeName = episode.title?.isNotEmpty == true
        ? episode.title!
        : 'Episode ${episode.number}';

    final offlineEpisode = LocalEpisode(
      folderName: folderName,
      name: episodeName,
      path: file.path,
    );

    final useOldPlayer = settingsController.preferences
        .get('useOldPlayer', defaultValue: false);

    if (useOldPlayer) {
      navigate(() => OfflineWatchPageOld(
            episodePath: offlineEpisode,
            episodesList: const [],
          ));
      return;
    }

    navigate(() => OfflineWatchPage(
          episode: offlineEpisode,
          episodeList: const [],
          currentEpisodeData: episode,
          episodeCatalog: widget.episodeList,
          anilistData: widget.anilistData,
          subtitleTracks: subtitleTracks,
        ));
  }

  HeadlessInAppWebView? headlessWebView;
  Timer? scrapingTimer;

  Future<void> fetchServers(Episode ep) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return SizedBox(
          width: double.infinity,
          child: settingsController.preferences
                  .get('universal_scrapper', defaultValue: false)
              ? _buildUniversalScraper(ep.link!)
              : FutureBuilder<List<Video>>(
                  future: sourceController.activeSource.value!.methods
                      .getVideoList(
                          DEpisode(episodeNumber: ep.number, url: ep.link)),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _buildScrapingLoadingState(true);
                    } else if (snapshot.hasError) {
                      return _buildErrorState(snapshot.error.toString());
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return _buildEmptyState();
                    } else {
                      streamList.value = snapshot.data
                              ?.map((e) => hive.Video.fromVideo(e))
                              .toList() ??
                          [];
                      return _buildServerList();
                    }
                  },
                ),
        );
      },
    );
  }

  Widget _buildUniversalScraper(String url) {
    return FutureBuilder<List<Video>>(
      future: _scrapeVideoStreams(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildScrapingLoadingState(false);
        } else if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState();
        } else {
          streamList.value = streamList.value =
              snapshot.data?.map((e) => hive.Video.fromVideo(e)).toList() ?? [];
          return _buildServerList();
        }
      },
    );
  }

  Future<List<Video>> _scrapeVideoStreams(String url) async {
    final completer = Completer<List<Video>>();
    final foundVideos = <Video>[];
    debugPrint('Calling => $url');

    await headlessWebView?.dispose();

    scrapingTimer = Timer(Duration(seconds: 30), () {
      headlessWebView?.dispose();
      if (!completer.isCompleted) {
        completer.complete(foundVideos);
      }
    });

    try {
      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          userAgent:
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
          javaScriptEnabled: true,
        ),
        onLoadStop: (controller, loadedUrl) async {
          await Future.delayed(Duration(seconds: 8));

          try {
            await controller.evaluateJavascript(source: """
          const playButtons = document.querySelectorAll('button[class*="play"], .play-button, [aria-label*="play"], [title*="play"]');
          playButtons.forEach(btn => btn.click());
          
          const videos = document.querySelectorAll('video');
          videos.forEach(video => {
            video.play().catch(e => {});
            video.click();
          });
          
          const containers = document.querySelectorAll('.video-container, .player-container, .video-player, .player');
          containers.forEach(container => container.click());
        """);
          } catch (e) {
            print('JavaScript execution error: $e');
          }

          await Future.delayed(Duration(seconds: 5));

          if (!completer.isCompleted) {
            completer.complete(foundVideos);
          }
        },
        shouldInterceptRequest: (controller, request) async {
          final requestUrl = request.url.toString();
          final headers = request.headers ?? {};
          print('Intercepted request: $requestUrl');

          if (_isVideoStream(requestUrl)) {
            final video = Video(
              requestUrl,
              _extractQuality(requestUrl),
              url,
              headers:
                  headers.isNotEmpty ? Map<String, String>.from(headers) : null,
            );

            final baseUrl = requestUrl.split('?')[0];
            if (!foundVideos.any((v) => v.url.split('?')[0] == baseUrl)) {
              foundVideos.add(video);
              print(
                  'Added video stream: $requestUrl (Quality: ${video.quality})');
            } else {
              print('Skipped duplicate stream: $requestUrl');
            }
          }

          return null;
        },
        onReceivedServerTrustAuthRequest: (controller, challenge) async {
          return ServerTrustAuthResponse(
              action: ServerTrustAuthResponseAction.PROCEED);
        },
      );

      await headlessWebView?.run();
    } catch (e) {
      print('Headless WebView error: $e');
      if (!completer.isCompleted) {
        completer.complete(foundVideos);
      }
    }

    final result = await completer.future;
    scrapingTimer?.cancel();
    await headlessWebView?.dispose();

    print('Final video count: ${result.length}');
    return result;
  }

  bool _isVideoStream(String url) {
    final lowercaseUrl = url.toLowerCase();
    return lowercaseUrl.contains('m3u8') ||
        lowercaseUrl.contains('.mp4') ||
        lowercaseUrl.contains('manifest') ||
        (lowercaseUrl.contains('video') &&
            (lowercaseUrl.contains('stream') ||
                lowercaseUrl.contains('play'))) ||
        lowercaseUrl.contains('playlist') ||
        lowercaseUrl.contains('.mpd');
  }

  String _extractQuality(String url) {
    final lowercaseUrl = url.toLowerCase();
    final filename = url.split('/').last.toLowerCase();

    if (filename.contains('master.m3u8')) return 'Auto';
    if (filename.contains('playlist.m3u8')) return 'Auto';

    final qualityPatterns = [
      RegExp(r'\b2160p\b', caseSensitive: false), // 4K
      RegExp(r'\b1080p\b', caseSensitive: false),
      RegExp(r'\b720p\b', caseSensitive: false),
      RegExp(r'\b480p\b', caseSensitive: false),
      RegExp(r'\b360p\b', caseSensitive: false),
      RegExp(r'\b240p\b', caseSensitive: false),
    ];

    final qualityLabels = ['4K', '1080p', '720p', '480p', '360p', '240p'];

    for (int i = 0; i < qualityPatterns.length; i++) {
      if (qualityPatterns[i].hasMatch(url)) {
        return qualityLabels[i];
      }
    }

    if (lowercaseUrl.contains('4k') || lowercaseUrl.contains('uhd')) {
      return '4K';
    }

    if (lowercaseUrl.contains('hd')) return 'HD';

    return url.split('/').last;
  }

  Widget _buildScrapingLoadingState(bool fromSrc) {
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExpressiveLoadingIndicator(),
          SizedBox(height: 16),
          Text(
            'Scanning for video streams...',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'This may take up to 30 seconds',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          10.height(),
          if (!fromSrc)
            AnymexChip(
              showCheck: false,
              isSelected: true,
              label: 'Using Universal Scrapper',
              onSelected: (v) {},
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    scrapingTimer?.cancel();
    headlessWebView?.dispose();
    super.dispose();
  }

  Widget _buildErrorState(String errorMessage) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        10.height(),
        AnymexText(
          text: "Error Occured",
          variant: TextVariant.bold,
          size: 18,
        ),
        20.height(),
        AnymexText(
          text: "Server-chan is taking a nap!",
          variant: TextVariant.semiBold,
          size: 18,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: AnymexText(
            text: errorMessage,
            variant: TextVariant.regular,
            size: 14,
            textAlign: TextAlign.center,
            color: Colors.red.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const SizedBox(
      height: 200,
      child: Center(
        child: AnymexText(
          text: "No servers available",
          variant: TextVariant.bold,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildServerList() {
    return Container(
      padding: const EdgeInsets.all(10),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: SuperListView(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            alignment: Alignment.center,
            child: const AnymexText(
              text: "Choose Server",
              size: 18,
              variant: TextVariant.bold,
            ),
          ),
          const SizedBox(height: 10),
          ...streamList.map((e) {
            return InkWell(
              onTap: () async {
                Get.back();
                final currentSource = sourceController.activeSource.value;
                if (currentSource != null) {
                  sourceController.recordSourceUsage(
                    type: ItemType.anime,
                    source: currentSource,
                  );
                }
                if (General.shouldAskForTrack.get(true) == false) {
                  navigate(() => settingsController.preferences
                          .get('useOldPlayer', defaultValue: false)
                      ? WatchPage(
                          episodeSrc: e,
                          episodeList: widget.episodeList,
                          anilistData: widget.anilistData!,
                          currentEpisode: selectedEpisode.value,
                          episodeTracks: streamList,
                          shouldTrack: true,
                        )
                      : WatchScreen(
                          episodeSrc: e,
                          episodeList: widget.episodeList,
                          anilistData: widget.anilistData!,
                          currentEpisode: selectedEpisode.value,
                          episodeTracks: streamList,
                        ));
                  return;
                }
                final shouldTrack = await showTrackingDialog(context);

                if (shouldTrack != null) {
                  navigate(() => settingsController.preferences
                          .get('useOldPlayer', defaultValue: false)
                      ? WatchPage(
                          episodeSrc: e,
                          episodeList: widget.episodeList,
                          anilistData: widget.anilistData!,
                          currentEpisode: selectedEpisode.value,
                          episodeTracks: streamList,
                          shouldTrack: shouldTrack,
                        )
                      : WatchScreen(
                          episodeSrc: e,
                          episodeList: widget.episodeList,
                          anilistData: widget.anilistData!,
                          currentEpisode: selectedEpisode.value,
                          episodeTracks: streamList,
                          shouldTrack: shouldTrack,
                        ));
                }
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 3.0, horizontal: 10),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 2.5, horizontal: 10),
                  title: AnymexText(
                    text: e.quality.toUpperCase(),
                    variant: TextVariant.bold,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  tileColor: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  trailing: const Icon(Iconsax.play5),
                  subtitle: AnymexText(
                    text: sourceController.activeSource.value!.name!
                        .toUpperCase(),
                    variant: TextVariant.semiBold,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class ContinueEpisodeButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String backgroundImage;
  final double height;
  final double borderRadius;
  final Color textColor;
  final TextStyle? textStyle;
  final Episode episode;
  final Episode progressEpisode;
  final Media data;

  const ContinueEpisodeButton({
    super.key,
    required this.onPressed,
    required this.backgroundImage,
    this.height = 60,
    this.borderRadius = 18,
    this.textColor = Colors.white,
    this.textStyle,
    required this.episode,
    required this.progressEpisode,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double progressPercentage;
        if (progressEpisode.number != episode.number ||
            progressEpisode.timeStampInMilliseconds == null ||
            progressEpisode.durationInMilliseconds == null ||
            progressEpisode.durationInMilliseconds! <= 0 ||
            progressEpisode.timeStampInMilliseconds! <= 0) {
          progressPercentage = 0.0;
        } else {
          progressPercentage = (progressEpisode.timeStampInMilliseconds! /
                  progressEpisode.durationInMilliseconds!)
              .clamp(0.0, 0.99);
        }

        return Container(
          width: double.infinity,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: NetworkSizedImage(
                    height: height,
                    width: double.infinity,
                    imageUrl: backgroundImage,
                    alignment: Alignment.topCenter,
                    radius: 0,
                    errorImage: data.cover ?? data.poster,
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.black.withOpacity(0.5),
                      Colors.black.withOpacity(0.5),
                    ]),
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                ),
              ),
              Positioned.fill(
                child: AnymexButton(
                  onTap: onPressed,
                  padding: EdgeInsets.zero,
                  border: BorderSide(color: Colors.transparent),
                  color: Colors.transparent,
                  radius: borderRadius,
                  child: SizedBox(
                    width: getResponsiveValue(context,
                        mobileValue: (Get.width * 0.8), desktopValue: null),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Episode ${episode.number}: ${episode.title}'
                              .toUpperCase(),
                          style: textStyle ??
                              TextStyle(
                                color: textColor,
                                fontFamily: 'Poppins-SemiBold',
                              ),
                          textAlign: TextAlign.center,
                        ),
                        PlatformBuilder(
                            androidBuilder: SizedBox.shrink(),
                            desktopBuilder: Column(
                              children: [
                                const SizedBox(height: 3),
                                Container(
                                  color: Theme.of(context).colorScheme.primary,
                                  height: 2,
                                  width: 6 *
                                      'Episode ${episode.number}: ${episode.title}'
                                          .length
                                          .toDouble(),
                                )
                              ],
                            ))
                      ],
                    ),
                  ),
                ),
              ),
              if (progressPercentage > 0)
                Positioned(
                  height: 2,
                  bottom: 0,
                  left: 0,
                  child: Container(
                    height: 4,
                    width: constraints.maxWidth * progressPercentage,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
