// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';

import 'package:anymex/controllers/download/download_controller.dart';
import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/screens/extensions/ExtensionSettings/ExtensionSettings.dart';
import 'package:anymex/utils/function.dart';
import 'package:anymex/utils/logger.dart';

import 'package:anymex/controllers/source/source_controller.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:anymex/models/Offline/Hive/chapter.dart';
import 'package:anymex/screens/manga/widgets/chapter_list_builder.dart';
import 'package:anymex/widgets/common/no_source.dart';
import 'package:anymex/widgets/custom_widgets/anymex_dropdown.dart';
import 'package:anymex/widgets/custom_widgets/anymex_progress.dart';
import 'package:anymex/widgets/header.dart';
import 'package:anymex/widgets/helper/tv_wrapper.dart';
import 'package:anymex/widgets/custom_widgets/custom_text.dart';
import 'package:anymex/widgets/custom_widgets/custom_textspan.dart';
import 'package:anymex/widgets/non_widgets/snackbar.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ChapterSection extends StatefulWidget {
  final RxString searchedTitle;
  final Media anilistData;
  final RxList<Chapter> chapterList;
  final SourceController sourceController;
  final Future<void> Function() mapToAnilist;
  final Future<void> Function(Media media) getDetailsFromSource;
  final void Function(
    BuildContext context,
    String title,
    Function(dynamic manga) onMangaSelected, {
    required bool isManga,
  }) showWrongTitleModal;

  const ChapterSection({
    super.key,
    required this.searchedTitle,
    required this.anilistData,
    required this.chapterList,
    required this.sourceController,
    required this.mapToAnilist,
    required this.getDetailsFromSource,
    required this.showWrongTitleModal,
  });

  @override
  State<ChapterSection> createState() => _ChapterSectionState();
}

class _ChapterSectionState extends State<ChapterSection> {
  late final DownloadController _downloadController;
  final RxBool _usingDownloadedSource = false.obs;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _downloadController = Get.find<DownloadController>();
    _applyStoredSource();
    _downloadController.refreshChapterCache(widget.anilistData.id);
  }

  @override
  void didUpdateWidget(covariant ChapterSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasChanged = oldWidget.anilistData.id != widget.anilistData.id ||
        oldWidget.anilistData.serviceType != widget.anilistData.serviceType;
    if (hasChanged) {
      _applyStoredSource();
    }
  }

  void _applyStoredSource() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.sourceController.applyStoredSourceSelection(
        type: ItemType.manga,
        media: widget.anilistData,
      );
    });
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  void _setDownloadedMode(bool value) {
    _usingDownloadedSource.value = value;
    if (value) {
      _fetchDownloadedChapters();
    }
  }

  Future<void> _fetchDownloadedChapters() async {
    await _downloadController.refreshChapterCache(widget.anilistData.id);
    widget.chapterList.value =
        _downloadController.buildChapterModels(widget.anilistData);
  }

  void _scheduleFallback() {
    _fallbackTimer?.cancel();
    if (_usingDownloadedSource.value) return;
    _fallbackTimer = Timer(const Duration(seconds: 40), () async {
      if (!mounted) return;
      if (widget.chapterList.value.isNotEmpty) return;
        final next = widget.sourceController
          .cycleToNextSource(ItemType.manga, recordUsage: false);
      if (next == null ||
          next.id == widget.sourceController.activeMangaSource.value?.id) {
        return;
      }
      successSnackBar('Switching to ${next.name} after no results.');
      await widget.mapToAnilist();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color:
                        Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .shadow
                          .withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 520;
                    final headerText = AnymexTextSpans(
                      spans: [
                        if (!widget.searchedTitle.value
                                .contains('Searching') &&
                            !widget.searchedTitle.value
                                .contains('No Match Found'))
                          AnymexTextSpan(
                            text: "Found: ",
                            size: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
                          ),
                        AnymexTextSpan(
                          text: widget.searchedTitle.value,
                          variant: TextVariant.semiBold,
                          size: 14,
                          color: widget.searchedTitle.value
                                  .contains('No Match Found')
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        )
                      ],
                    );
                    final cta = Align(
                      alignment: isCompact
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: _buildWrongTitleButton(context),
                    );

                    if (isCompact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          headerText,
                          const SizedBox(height: 12),
                          cta,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: headerText),
                        const SizedBox(width: 12),
                        cta,
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Obx(() => buildMangaSourceDropdown()),
              const SizedBox(height: 20),
              const Row(
                children: [
                  AnymexText(
                    text: "Chapters",
                    variant: TextVariant.bold,
                    size: 18,
                  ),
                ],
              ),
              if (widget.sourceController.activeMangaSource.value == null &&
                  !_usingDownloadedSource.value)
                const NoSourceSelectedWidget()
              else if (widget.chapterList.value.isEmpty)
                const SizedBox(
                  height: 500,
                  child: Center(child: AnymexProgressIndicator()),
                )
              else
                widget.searchedTitle.value != "No match found"
                    ? Obx(() => ChapterListBuilder(
                          chapters: widget.chapterList,
                          anilistData: widget.anilistData,
                          showingDownloaded: _usingDownloadedSource.value,
                          downloadedEntries:
                              _downloadController.chapterCache[widget.anilistData.id] ??
                                  const [],
                        ))
                    : const Center(child: AnymexText(text: "No Match Found"))
            ],
          ),
        ));
  }

  Widget _buildWrongTitleButton(BuildContext context) {
    return AnymexOnTap(
      onTap: () {
        widget.showWrongTitleModal(
          context,
          widget.anilistData.title,
          (manga) async {
            widget.chapterList.value = [];
            await widget.getDetailsFromSource(
                Media.froDMedia(manga, ItemType.manga));
            final key =
                '${widget.sourceController.activeMangaSource.value?.id}-${widget.anilistData.id}-${widget.anilistData.serviceType.index}';
            settingsController.preferences.put(key, manga.title);
          },
          isManga: true,
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.swap_horiz_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              AnymexText(
                text: "Wrong Title?",
                size: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void openSourcePreferences(BuildContext context) {
    navigate(
      () => SourcePreferenceScreen(
        source: widget.sourceController.activeMangaSource.value!,
      ),
    );
  }

  Widget buildMangaSourceDropdown() {
    DropdownItem _buildSourceDropdownItem(Source source,
        {bool highlighted = false}) {
      final isMangayomi = source.extensionType == ExtensionType.mangayomi;
      return DropdownItem(
        value: source.id?.toString() ?? source.name ?? 'unknown',
        text: source.name?.toUpperCase() ?? 'UNKNOWN SOURCE',
        subtitle: source.lang?.toUpperCase() ?? 'UNKNOWN',
        leadingIcon: NetworkSizedImage(
          radius: 16,
          imageUrl: isMangayomi
              ? "https://raw.githubusercontent.com/kodjodevf/mangayomi/main/assets/app_icons/icon-red.png"
              : 'https://aniyomi.org/img/logo-128px.png',
          height: 24,
          width: 24,
        ),
        backgroundColor: highlighted
            ? Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withOpacity(0.35)
            : null,
      );
    }

    final downloadedItem = DropdownItem(
      value: DownloadController.downloadedSourceValue,
      text: DownloadController.downloadedSourceLabel.toUpperCase(),
      subtitle: 'Offline Library',
      leadingIcon: Icon(
        Icons.download_done_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    final installedSources =
        widget.sourceController.installedMangaExtensions.toList();
    final topSources =
        widget.sourceController.getTopSources(ItemType.manga, limit: 5);
    final favoriteIds = topSources
        .map((source) => source.id?.toString())
        .whereType<String>()
        .toSet();

    final favoriteItems = topSources
        .map((source) => _buildSourceDropdownItem(source, highlighted: true))
        .toList();

    final regularItems = installedSources
        .where((source) =>
            !favoriteIds.contains(source.id?.toString() ?? ''))
        .map((source) => _buildSourceDropdownItem(source))
        .toList();

    final items = <DropdownItem>[downloadedItem];
    if (favoriteItems.isNotEmpty) {
      items.add(const DropdownItem.section(
        value: '__top_manga_sources__',
        text: 'MOST USED',
      ));
      items.addAll(favoriteItems);
      items.add(const DropdownItem.section(
        value: '__all_manga_sources__',
        text: 'ALL SOURCES',
      ));
    }
    items.addAll(regularItems);

    DropdownItem? selectedItem;
    if (_usingDownloadedSource.value) {
      selectedItem = downloadedItem;
    } else {
      final activeSource = widget.sourceController.activeMangaSource.value;
      if (activeSource != null) {
        final isFavorite =
            favoriteIds.contains(activeSource.id?.toString() ?? '');
        selectedItem = _buildSourceDropdownItem(activeSource,
            highlighted: isFavorite);
      } else if (items.isNotEmpty) {
        selectedItem = null;
      }
    }

    return AnymexDropdown(
      items: items,
      selectedItem: selectedItem,
      label: "SELECT SOURCE",
      icon: Icons.extension_rounded,
      actionIcon: Icons.settings_outlined,
      onActionPressed: () => openSourcePreferences(Get.context!),
      enableSearch: true,
      onChanged: (DropdownItem item) async {
        if (item.value == DownloadController.downloadedSourceValue) {
          _setDownloadedMode(true);
          if (mounted) setState(() {});
          return;
        }

        _setDownloadedMode(false);
        widget.chapterList.value = [];
        try {
          final selectedSource = widget.sourceController.installedMangaExtensions
              .firstWhereOrNull((source) =>
                  source.id?.toString() == item.value || source.name == item.value);
          if (selectedSource != null) {
            widget.sourceController.rememberSourceSelectionForMedia(
              type: ItemType.manga,
              media: widget.anilistData,
              source: selectedSource,
            );
            widget.sourceController.setActiveSource(selectedSource);
          }
          _scheduleFallback();
          await widget.mapToAnilist();
          if (mounted) setState(() {});
        } catch (e) {
          Logger.i(e.toString());
        }
      },
    );
  }
}
