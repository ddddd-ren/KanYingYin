import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/utils/version_history.dart';

class VersionChangelogDialog extends StatelessWidget {
  const VersionChangelogDialog({super.key, required this.versions});

  final List<VersionHistory> versions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('版本更新日志'),
      content: VersionChangelogContent(versions: versions),
      actions: [
        TextButton(
          onPressed: () => AppDialog.dismiss<void>(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

class VersionChangelogContent extends StatelessWidget {
  const VersionChangelogContent({super.key, required this.versions});

  final List<VersionHistory> versions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final version in versions) ...[
            Text(
              'v${version.version}  ${version.releaseLabel}  ${version.date}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final change in version.changes)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Text(
                  '- $change',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
