import 'package:anymex/models/Offline/Hive/chapter.dart';
import 'package:anymex/widgets/common/glow.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ChapterRanges extends StatelessWidget {
  final RxInt selectedChunkIndex;
  final ValueChanged<int> onChunkSelected;
  final List<List<Chapter>> chunks;

  const ChapterRanges({
    super.key,
    required this.selectedChunkIndex,
    required this.onChunkSelected,
    required this.chunks,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color _chipColor(bool selected) => Color.alphaBlend(
          scheme.primary.withOpacity(selected ? 0.18 : 0.06),
          scheme.surfaceVariant,
        );
    Color _borderColor(bool selected) => selected
        ? scheme.primary.withOpacity(0.55)
        : scheme.outline.withOpacity(0.4);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(
          chunks.length,
          (index) {
            final isSelected = selectedChunkIndex.value == index;
            final label = index == 0
                ? 'All'
                : '${chunks[index].first.number} - ${chunks[index].last.number}';
            return Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 10, 5),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (!isSelected) {
                    selectedChunkIndex.value = index;
                    onChunkSelected(index);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: _chipColor(isSelected),
                    border: Border.all(color: _borderColor(isSelected)),
                    boxShadow:
                      isSelected ? [lightGlowingShadow(context)] : const [],
                  ),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
