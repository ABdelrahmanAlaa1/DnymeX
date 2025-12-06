import 'package:anymex/controllers/settings/settings.dart';
import 'package:anymex/controllers/source/source_controller.dart';
import 'package:anymex/widgets/common/glow.dart';
import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:hugeicons/hugeicons.dart';

class GitHubRepoDialog extends StatefulWidget {
  final ItemType type;
  final ExtensionType extType;

  const GitHubRepoDialog({
    super.key,
    required this.type,
    required this.extType,
  });

  @override
  State<GitHubRepoDialog> createState() => _GitHubRepoDialogState();

  void show({
    required BuildContext context,
  }) {
    showDialog(
      context: context,
      builder: (context) => GitHubRepoDialog(type: type, extType: extType),
    );
  }
}

class _GitHubRepoDialogState extends State<GitHubRepoDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _textScrollController = ScrollController();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      setState(() {
        final repos = _currentRepoList();
        _controller.text = repos.join('\n');
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _textScrollController.dispose();
    super.dispose();
  }

  int get _lineLimit {
    final value = settingsController.repoLinkLineLimit;
    return value.clamp(2, 5).toInt();
  }

  double _lineHeight(TextStyle style) {
    final fontSize = style.fontSize ?? 14;
    final height = style.height ?? 1.3;
    return fontSize * height;
  }

  int _estimateVisualLines(
    String text,
    double maxWidth,
    TextStyle style,
    TextDirection direction,
  ) {
    if (maxWidth.isNaN || maxWidth <= 0) {
      return text.isEmpty ? 1 : text.split('\n').length;
    }
    final displayText = text.isEmpty ? ' ' : text;
    final painter = TextPainter(
      text: TextSpan(text: displayText, style: style),
      textDirection: direction,
      maxLines: null,
    );
    painter.layout(maxWidth: maxWidth);
    final metrics = painter.computeLineMetrics();
    return metrics.isEmpty ? 1 : metrics.length;
  }

  List<String> _parseEntries(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  List<String> _currentRepoList() {
    switch (widget.type) {
      case ItemType.anime:
        return sourceController.getAnimeRepo(widget.extType);
      case ItemType.manga:
        return sourceController.getMangaRepo(widget.extType);
      case ItemType.novel:
        return sourceController.activeNovelRepo;
    }
  }

  String? _validateUrl(List<String> urls) {
    if (urls.isEmpty) {
      return 'Please enter at least one repository URL';
    }

    return null;
  }

  void _handleSubmit() async {
    final urls = _parseEntries(_controller.text);
    final error = _validateUrl(urls);

    setState(() {
      _errorMessage = error;
    });

    if (error == null) {
      setState(() {
        _isLoading = true;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      switch (widget.type) {
        case ItemType.anime:
          sourceController.setAnimeRepo(urls, widget.extType);
          break;

        case ItemType.manga:
          sourceController.setMangaRepo(urls, widget.extType);
          break;

        case ItemType.novel:
          sourceController.activeNovelRepo = urls;
          break;
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.primary;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              Color.alphaBlend(accent.withOpacity(0.12), colorScheme.surface),
              Color.alphaBlend(
                  accent.withOpacity(0.04), colorScheme.surfaceVariant),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: accent.withOpacity(0.2)),
          boxShadow: [lightGlowingShadow(context)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.alphaBlend(
                        accent.withOpacity(0.16),
                        colorScheme.surfaceContainerHighest),
                    Color.alphaBlend(
                        accent.withOpacity(0.04), colorScheme.surface),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      HugeIcons.strokeRoundedGithub,
                      color: colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add ${widget.type.name.toUpperCase()} Repository',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Enter GitHub repository URL',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repository URL',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final textStyle = theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            height: 1.32,
                          ) ??
                          TextStyle(
                            fontSize: 14,
                            height: 1.32,
                            color: colorScheme.onSurface,
                          );
                      final contentPadding = const EdgeInsets.fromLTRB(16, 18, 16, 34);
                      final double paddingWidth =
                          contentPadding.horizontal + 38; // prefix width
                      final double availableWidth =
                          (constraints.maxWidth - paddingWidth).clamp(120.0, constraints.maxWidth);
                      final int measuredLines = _estimateVisualLines(
                        _controller.text,
                        availableWidth,
                        textStyle,
                        Directionality.of(context),
                      );
                      final int limit = _lineLimit;
                      final bool needsScroll = measuredLines >= limit;
                      final int displayLines = limit + 1;
                      final double lineHeight = _lineHeight(textStyle);
                      final double fieldHeight =
                          (lineHeight * displayLines) + contentPadding.vertical;
                      final ScrollPhysics physics = needsScroll
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics();

                      Widget textField = TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        scrollController: _textScrollController,
                        scrollPhysics: physics,
                        minLines: displayLines,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: InputDecoration(
                          hintText: 'https://github.com/username/repo.json',
                          hintStyle: TextStyle(
                            color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            HugeIcons.strokeRoundedLink01,
                            color: colorScheme.onSurfaceVariant,
                            size: 18,
                          ),
                          border: InputBorder.none,
                          contentPadding: contentPadding,
                        ),
                        style: textStyle.copyWith(color: colorScheme.onSurface),
                        onSubmitted: (_) => _handleSubmit(),
                        onChanged: (value) {
                          setState(() {
                            _errorMessage = null;
                          });
                        },
                      );

                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            colors: [
                              Color.alphaBlend(
                                  accent.withOpacity(0.18),
                                  colorScheme.surfaceContainerLow),
                              Color.alphaBlend(
                                  accent.withOpacity(0.05),
                                  colorScheme.surfaceVariant),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: (_errorMessage != null
                                    ? colorScheme.error
                                    : accent)
                                .withOpacity(_errorMessage != null ? 0.7 : 0.3),
                          ),
                          boxShadow: [
                            if (_errorMessage != null)
                              BoxShadow(
                                color: colorScheme.error.withOpacity(0.3),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              )
                            else
                              lightGlowingShadow(context),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Stack(
                            children: [
                              SizedBox(
                                height: fieldHeight,
                                child: Scrollbar(
                                  controller: _textScrollController,
                                  thumbVisibility: needsScroll,
                                  trackVisibility: needsScroll,
                                  child: textField,
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 16,
                                right: 16,
                                child: IgnorePointer(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 1.2,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                colorScheme.onSurfaceVariant
                                                    .withOpacity(0.05),
                                                accent.withOpacity(0.2),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.add_rounded,
                                        size: 16,
                                        color: accent.withOpacity(0.45),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedAlert02,
                          size: 16,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 32),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: ExpressiveLoadingIndicator(
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : Text(
                                  'Add Repository',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onPrimary,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}
