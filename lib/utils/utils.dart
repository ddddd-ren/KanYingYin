// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/utils/display_utils.dart';
import 'package:kanyingyin/utils/encoding_utils.dart';
import 'package:kanyingyin/utils/time_utils.dart';
import 'package:kanyingyin/utils/video_utils.dart';
import 'package:kanyingyin/utils/window_utils.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class Utils {
  static final Random random = Random();

  static String getRandomUA() {
    final random = Random();
    String randomElement =
        userAgentsList[random.nextInt(userAgentsList.length)];
    return randomElement;
  }

  static String getRandomAcceptedLanguage() {
    final random = Random();
    String randomElement =
        acceptLanguageList[random.nextInt(acceptLanguageList.length)];
    return randomElement;
  }

  static String makeHeroTag(Object v) {
    return v.toString() + random.nextInt(9999).toString();
  }

  static ThemeData oledDarkTheme(ThemeData defaultDarkTheme) {
    return defaultDarkTheme.copyWith(
      scaffoldBackgroundColor: const Color(0xFF121218),
      colorScheme: defaultDarkTheme.colorScheme.copyWith(
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        surface: const Color(0xFF1E1E2E),
        onSurface: Colors.white,
      ),
    );
  }

  static Future<String> getPlayerTempPath() async {
    final directory = await getTemporaryDirectory();
    return directory.path;
  }

  static String buildShadersAbsolutePath(
      String baseDirectory, List<String> shaders) {
    List<String> absolutePaths = shaders.map((shader) {
      return path.join(baseDirectory, shader);
    }).toList();
    return absolutePaths.join(';');
  }

  // Delegates to split files
  static Future<bool> isLowResolution() => DisplayUtils.isLowResolution();
  static Future<Map<String, double>> getScreenInfo() =>
      DisplayUtils.getScreenInfo();
  static bool isDesktop() => DisplayUtils.isDesktop();
  static bool isWideScreen() => DisplayUtils.isWideScreen();
  static bool isTablet() => DisplayUtils.isTablet();
  static bool isCompact() => DisplayUtils.isCompact();
  static Future<void> enterWindowsFullscreen() =>
      WindowUtils.enterWindowsFullscreen();
  static Future<void> exitWindowsFullscreen() =>
      WindowUtils.exitWindowsFullscreen();
  static Future<void> enterFullScreen({bool lockOrientation = true}) =>
      WindowUtils.enterFullScreen(lockOrientation: lockOrientation);
  static Future<void> exitFullScreen({bool lockOrientation = true}) =>
      WindowUtils.exitFullScreen(lockOrientation: lockOrientation);
  static String formatTimestampToRelativeTime(int timeStamp) =>
      TimeUtils.formatTimestampToRelativeTime(timeStamp);
  static String dateFormat(int timeStamp, {String formatType = 'list'}) =>
      TimeUtils.dateFormat(timeStamp, formatType: formatType);
  static String CustomStamp_str(
          {int? timestamp,
          String? date,
          bool toInt = true,
          String? formatType}) =>
      TimeUtils.CustomStamp_str(
          timestamp: timestamp,
          date: date,
          toInt: toInt,
          formatType: formatType);
  static String durationToString(Duration duration) =>
      TimeUtils.durationToString(duration);
  static String formatDate(String dateString) =>
      TimeUtils.formatDate(dateString);
  static int dateStringToWeekday(String dateString) =>
      TimeUtils.dateStringToWeekday(dateString);
  static String getSeasonStringByMonth(int month) =>
      TimeUtils.getSeasonStringByMonth(month);
  static bool isSameSeason(DateTime d1, DateTime d2) =>
      TimeUtils.isSameSeason(d1, d2);

  static String decodeVideoSource(String iframeUrl) =>
      VideoUtils.decodeVideoSource(iframeUrl);
  static int extractEpisodeNumber(String input) =>
      VideoUtils.extractEpisodeNumber(input);
  static String formatTraceSimilarity(double? similarity,
          {int fractionDigits = 1, String empty = '--'}) =>
      VideoUtils.formatTraceSimilarity(similarity,
          fractionDigits: fractionDigits, empty: empty);

  static Future<String> calculateFileHash(File file) =>
      EncodingUtils.calculateFileHash(file);
}
