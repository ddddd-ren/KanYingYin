enum MediaLibraryCategory { movie, anime, tvSeries }

extension MediaLibraryCategoryLabel on MediaLibraryCategory {
  String get label => switch (this) {
        MediaLibraryCategory.movie => '电影',
        MediaLibraryCategory.anime => '动漫',
        MediaLibraryCategory.tvSeries => '电视剧',
      };
}
