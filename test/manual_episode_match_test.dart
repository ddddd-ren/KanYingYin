import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';

void main() {
  const items = <ManualEpisodeMatchItem>[
    ManualEpisodeMatchItem(
      resourceId: 'video-a',
      originalName: 'Show.S01E01.mkv',
      automaticSeasonNumber: 1,
      automaticEpisodeNumber: 1,
    ),
    ManualEpisodeMatchItem(
      resourceId: 'video-b',
      originalName: 'Show.1080p.mkv',
    ),
  ];

  test('允许多个视频映射到同一集', () {
    final errors = validateManualEpisodeAssignments(
      items: items,
      assignments: <ManualEpisodeAssignment>[
        ManualEpisodeAssignment.mapped(
          resourceId: 'video-a',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        ManualEpisodeAssignment.mapped(
          resourceId: 'video-b',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ],
      selectedSeasonNumber: 1,
      validEpisodeNumbers: const <int>{1, 2},
    );

    expect(errors, isEmpty);
  });

  test('拒绝重复资源标识和不属于当前季度的集号', () {
    const duplicateItems = <ManualEpisodeMatchItem>[
      ManualEpisodeMatchItem(resourceId: 'same', originalName: 'a.mkv'),
      ManualEpisodeMatchItem(resourceId: 'same', originalName: 'b.mkv'),
    ];
    final errors = validateManualEpisodeAssignments(
      items: duplicateItems,
      assignments: <ManualEpisodeAssignment>[
        ManualEpisodeAssignment.mapped(
          resourceId: 'same',
          seasonNumber: 2,
          episodeNumber: 3,
        ),
      ],
      selectedSeasonNumber: 1,
      validEpisodeNumbers: const <int>{1, 2},
    );

    expect(errors, contains('资源标识必须唯一：same'));
    expect(errors, contains('same 的季度不是当前选择的第 1 季'));
    expect(errors, contains('same 选择了不存在的第 3 集'));
  });

  test('三种赋值操作保持明确且强类型', () {
    final mapped = ManualEpisodeAssignment.mapped(
      resourceId: 'video-a',
      seasonNumber: 1,
      episodeNumber: 2,
    );
    final keepOriginal = ManualEpisodeAssignment.keepOriginal('video-a');
    final restore = ManualEpisodeAssignment.restoreAutomatic('video-a');

    expect(mapped.mode, ManualEpisodeAssignmentMode.mapped);
    expect(mapped.seasonNumber, 1);
    expect(mapped.episodeNumber, 2);
    expect(keepOriginal.mode, ManualEpisodeAssignmentMode.keepOriginal);
    expect(keepOriginal.seasonNumber, isNull);
    expect(restore.mode, ManualEpisodeAssignmentMode.restoreAutomatic);
    expect(restore.episodeNumber, isNull);
  });
}
