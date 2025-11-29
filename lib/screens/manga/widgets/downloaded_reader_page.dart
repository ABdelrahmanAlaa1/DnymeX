import 'dart:io';

import 'package:anymex/controllers/download/download_controller.dart';
import 'package:anymex/models/Media/media.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class DownloadedReaderPage extends StatefulWidget {
  final Media media;
  final DownloadedChapter chapter;

  const DownloadedReaderPage({
    super.key,
    required this.media,
    required this.chapter,
  });

  @override
  State<DownloadedReaderPage> createState() => _DownloadedReaderPageState();
}

class _DownloadedReaderPageState extends State<DownloadedReaderPage> {
  late final PageController _pageController;
  int _currentIndex = 0;

  List<String> get _absoluteFiles => widget.chapter.files
      .map((file) => p.join(widget.chapter.directory.path, file))
      .toList();

  String _displayTitle() {
    final title = widget.media.title;
    if (title == null) return 'Downloaded chapter';

    if (title is String) {
      return title.isNotEmpty ? title : 'Downloaded chapter';
    }

    if (title is Map) {
      for (final key in ['userPreferred', 'romaji', 'english', 'title']) {
        final value = title[key];
        if (value is String && value.isNotEmpty) {
          return value;
        }
      }
    }

    try {
      final dynamic dyn = title;
      final userPreferred = dyn.userPreferred;
      if (userPreferred is String && userPreferred.isNotEmpty) {
        return userPreferred;
      }
      final romaji = dyn.romaji;
      if (romaji is String && romaji.isNotEmpty) {
        return romaji;
      }
      final english = dyn.english;
      if (english is String && english.isNotEmpty) {
        return english;
      }
    } catch (_) {
      // ignore dynamic access failures
    }

    return title.toString().isNotEmpty ? title.toString() : 'Downloaded chapter';
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _jumpTo(int index) {
    if (index < 0 || index >= _absoluteFiles.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = _absoluteFiles.where((path) => File(path).existsSync()).toList();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _displayTitle(),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Chapter ${widget.chapter.chapterNumber.toStringAsFixed(0)}'
              '${widget.chapter.title != null ? ' • ${widget.chapter.title}' : ''}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Center(
              child: Text(
                '${_currentIndex + 1}/${files.length}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: files.isEmpty
          ? Center(
              child: Text(
                'No pages available for this chapter.',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            )
          : PageView.builder(
              controller: _pageController,
              itemCount: files.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                final file = File(files[index]);
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Center(
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: files.length < 2
          ? null
          : Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: _currentIndex > 0 ? () => _jumpTo(_currentIndex - 1) : null,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                  ),
                  Text(
                    'Page ${_currentIndex + 1} of ${files.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  IconButton(
                    onPressed: _currentIndex < files.length - 1
                        ? () => _jumpTo(_currentIndex + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                  ),
                ],
              ),
            ),
    );
  }
}
