import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

enum CloudResourceCardKind { media, directory }

class CloudResourceCardViewData {
  CloudResourceCardViewData({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.details,
    required List<ImmersiveMediaCardBadge> badges,
    required this.isScraping,
    this.posterCachePath,
    this.posterUrl,
  }) : badges = List<ImmersiveMediaCardBadge>.unmodifiable(badges);

  factory CloudResourceCardViewData.fromEntry({
    required CloudFileEntry entry,
    required CloudResourceTmdbRecord? record,
    required bool scraping,
    required bool hasSubtitle,
  }) {
    final matched = record?.status == CloudResourceTmdbStatus.matched;
    final kind = !entry.isDirectory || matched
        ? CloudResourceCardKind.media
        : CloudResourceCardKind.directory;
    final effectiveTitle = record?.effectiveTitle.trim();
    final title = effectiveTitle != null && effectiveTitle.isNotEmpty
        ? effectiveTitle
        : entry.name;
    final details = <String>[];
    if (matched) {
      final rating = record?.rating;
      if (rating != null) details.add('${rating.toStringAsFixed(1)} ★');
      final mediaType = record?.mediaType;
      if (mediaType != null) details.add(_formatMediaType(mediaType));
      final year = _releaseYear(record?.releaseDate);
      if (year != null) details.add(year);
    }
    if (!entry.isDirectory) details.add(_formatBytes(entry.size));

    final badges = <ImmersiveMediaCardBadge>[];
    if (kind == CloudResourceCardKind.media) {
      if (!entry.isDirectory && hasSubtitle) {
        badges.add(
          const ImmersiveMediaCardBadge(
            icon: Icons.closed_caption_outlined,
            label: '有字幕',
          ),
        );
      }
      badges.add(_scrapeBadge(record?.status, scraping: scraping));
    }

    return CloudResourceCardViewData(
      kind: kind,
      title: title,
      subtitle: title == entry.name ? '' : entry.name,
      details: details.join('  ·  '),
      badges: badges,
      isScraping: scraping,
      posterCachePath: matched ? record?.posterCachePath : null,
      posterUrl: matched ? record?.posterUrl : null,
    );
  }

  final CloudResourceCardKind kind;
  final String title;
  final String subtitle;
  final String details;
  final List<ImmersiveMediaCardBadge> badges;
  final bool isScraping;
  final String? posterCachePath;
  final String? posterUrl;

  static ImmersiveMediaCardBadge _scrapeBadge(
    CloudResourceTmdbStatus? status, {
    required bool scraping,
  }) {
    if (scraping) {
      return const ImmersiveMediaCardBadge(
        icon: Icons.image_search_outlined,
        label: '刮削中',
        loading: true,
      );
    }
    final label = switch (status) {
      CloudResourceTmdbStatus.matched => '已刮削',
      CloudResourceTmdbStatus.unmatched => '未匹配',
      CloudResourceTmdbStatus.failed => '刮削失败',
      CloudResourceTmdbStatus.unchecked || null => '未刮削',
    };
    return ImmersiveMediaCardBadge(
      icon: Icons.image_search_outlined,
      label: label,
    );
  }

  static String _formatMediaType(TmdbMediaType mediaType) {
    return switch (mediaType) {
      TmdbMediaType.movie => '电影',
      TmdbMediaType.tv => '电视剧',
    };
  }

  static String? _releaseYear(String? releaseDate) {
    if (releaseDate == null) return null;
    final match = RegExp(r'^(\d{4})').firstMatch(releaseDate.trim());
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    return year != null && year >= 1000 ? year.toString() : null;
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}
