part of 'player_controller.dart';

/// 播放生命周期、音轨字幕、Anime4K 和控制操作；控制器只保留状态外观。
mixin _PlayerPlaybackApplicationCoordinator on _PlayerController {
  late final Anime4kCoordinator _anime4kCoordinator = Anime4kCoordinator(
    policy: const Anime4kPolicy(),
    execute: _executeAnime4kDecision,
  );

  PlayerLifecycleToken activatePlaybackLifecycle() {
    _disposeRequested = false;
    _disposeFuture = null;
    return _lifecycleOperations.activate();
  }

  Future<void> init(
    PlaybackInitParams params, {
    required PlayerLifecycleToken lifecycleToken,
  }) {
    if (!_lifecycleOperations.isCurrent(lifecycleToken) || _disposeRequested) {
      return _playbackLeaseCoordinator.reject(params.lease);
    }
    final token = _mediaOperations.beginMedia(params.stableMediaKey);
    return _playerInitLock.synchronized(
      () => _init(params, token, lifecycleToken),
    );
  }

  Future<void> _init(
    PlaybackInitParams params,
    PlayerMediaToken mediaToken,
    PlayerLifecycleToken lifecycleToken,
  ) async {
    final previousParams = _lastInitParams;
    var adopted = false;
    var replacementAborted = false;
    try {
      final initialized = await _initializeMedia(
        params,
        mediaToken,
        lifecycleToken,
      );
      if (!initialized ||
          !_isMediaOperationActive(mediaToken, lifecycleToken)) {
        _lastInitParams = previousParams;
        return;
      }
      await _playbackLeaseCoordinator.adopt(params.lease);
      adopted = true;
    } on Object {
      _lastInitParams = previousParams;
      replacementAborted = true;
      await _playbackLeaseCoordinator.abortReplacement(params.lease);
      rethrow;
    } finally {
      if (!adopted && !replacementAborted) {
        await _playbackLeaseCoordinator.reject(params.lease);
      }
    }
  }

  Future<bool> _initializeMedia(
    PlaybackInitParams params,
    PlayerMediaToken mediaToken,
    PlayerLifecycleToken lifecycleToken,
  ) async {
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return false;
    final bool isNewMedia = _lastInitParams?.videoUrl != params.videoUrl;
    if (isNewMedia) {
      _truehdAudioTrackFallbackAttempted = false;
      _softwareVideoDecoderFallbackAttempted = false;
      _decoderRecoveryPolicy.reset();
      _resetEmbeddedTrackState();
    }
    _lastInitParams = params;
    timelineSegments.clear();
    _timelineMediaRevision =
        params.mediaRevision ?? 'remote:${params.totalBytes ?? ''}';
    _embeddedTrackCoordinator.beginMedia(_currentTrackLanguageMediaKey());
    videoUrl = params.videoUrl;
    isLocalPlayback = params.isLocalPlayback;
    _subtitleStorageKey = params.subtitleStorageKey;
    _loadSubtitleDelayForCurrentVideo();
    mediaId = params.mediaId;
    currentEpisode = params.episode;
    currentRoad = params.currentRoad;
    referer = params.referer;
    _applyStoredSubtitleStyle();
    if (isNewMedia) {
      lastSubtitlePath = params.subtitlePath ?? '';
    }
    _setCurrentSubtitlePath(params.subtitlePath ?? '');
    if (!params.isLocalPlayback) {
      subtitleCandidates.clear();
    }

    AppLogger().i(
      'PlayerController: ${params.isLocalPlayback ? "local" : "online"} '
      'playback: ${sanitizeMediaDescription(params.videoUrl, isLocalPlayback: params.isLocalPlayback)} '
      'route=${params.networkRoute.name}',
    );

    playing = false;
    loading = true;
    isBuffering = true;
    currentPosition = Duration.zero;
    buffer = Duration.zero;
    duration = Duration.zero;
    completed = false;
    if (params.isLocalPlayback) {
      try {
        final stat = await File(params.videoUrl).stat();
        _timelineMediaRevision = stat.type == FileSystemEntityType.file
            ? 'file:${stat.size}:${stat.modified.microsecondsSinceEpoch}'
            : 'unverified:${mediaToken.hashCode}';
      } on FileSystemException {
        _timelineMediaRevision = 'unverified:${mediaToken.hashCode}';
      }
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return false;
    }
    final runtimeSettings = _runtimePreferences.load();
    androidAutoEnterPip = runtimeSettings.androidAutoEnterPip;
    playerSpeed = runtimeSettings.playSpeed;
    aspectRatioType = runtimeSettings.aspectRatioType;
    buttonSkipTime = runtimeSettings.buttonSkipTime;
    arrowKeySkipTime = runtimeSettings.arrowKeySkipTime;
    await _disposePlayerResources();
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return false;
    int episodeFromTitle = 0;
    try {
      episodeFromTitle = Utils.extractEpisodeNumber(params.episodeTitle);
    } catch (e) {
      AppLogger().e(
          'PlayerController: failed to extract episode number from title',
          error: e);
    }
    if (episodeFromTitle == 0) {
      episodeFromTitle = params.episode;
    }
    if (params.isLocalPlayback) {
      await refreshSubtitleCandidates();
    }
    try {
      mediaPlayer = await createVideoController(
        params.httpHeaders,
        mediaToken: mediaToken,
        lifecycleToken: lifecycleToken,
        initParams: params,
        offset: params.offset,
        subtitlePath: params.subtitlePath,
      );
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
        await _disposePlayerResources();
        return false;
      }

      volume = volume != -1 ? volume : 100;
      await setVolume(volume);
      setPlaybackSpeed(playerSpeed);
      AppLogger().i('PlayerController: video initialized');
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
        await _disposePlayerResources();
        return false;
      }
      loading = false;

      coverUrl = params.coverUrl;
      return true;
    } catch (e) {
      if (e is _PlayerInitializationCancelled) return false;
      loading = false;
      isBuffering = false;
      AppLogger().e('PlayerController: failed to initialize video', error: e);
      try {
        await _disposePlayerResources().timeout(const Duration(seconds: 5));
      } catch (disposeError) {
        AppLogger().w(
          'PlayerController: failed to dispose after init error',
          error: disposeError,
        );
      }
      rethrow;
    }
  }

  Future<void> setupPlayerDebugInfoSubscription() async {
    await playerLogSubscription?.cancel();
    playerLogSubscription = mediaPlayer!.stream.log.listen((event) {
      _decoderRecoveryPolicy.recordLog(event);
      final safeLog = sanitizePlayerDiagnostic(event.toString());
      writePlayerLog('MPV: $safeLog');
      if (playerDebugMode) {
        playerLog.add(safeLog);
      }
    });
    await playerWidthSubscription?.cancel();
    playerWidthSubscription = mediaPlayer!.stream.width.listen((event) {
      playerWidth = event ?? 0;
      _scheduleAnime4kEvaluation();
    });
    await playerHeightSubscription?.cancel();
    playerHeightSubscription = mediaPlayer!.stream.height.listen((event) {
      playerHeight = event ?? 0;
      _scheduleAnime4kEvaluation();
    });
    await playerVideoParamsSubscription?.cancel();
    playerVideoParamsSubscription =
        mediaPlayer!.stream.videoParams.listen((event) {
      playerVideoParams = event.toString();
      _logPlayerColorDiagnostic(event);
    });
    await playerAudioParamsSubscription?.cancel();
    playerAudioParamsSubscription =
        mediaPlayer!.stream.audioParams.listen((event) {
      playerAudioParams = event.toString();
    });
    await playerPlaylistSubscription?.cancel();
    playerPlaylistSubscription = mediaPlayer!.stream.playlist.listen((event) {
      playerPlaylist = sanitizePlayerDiagnostic(event.toString());
    });
    await playerTracksSubscription?.cancel();
    playerTracksSubscription = mediaPlayer!.stream.track.listen((event) {
      selectedAudioTrackId = event.audio.id;
      if (!event.subtitle.uri && !event.subtitle.data) {
        selectedEmbeddedSubtitleTrackId =
            event.subtitle.id == 'no' || event.subtitle.id == 'auto'
                ? ''
                : event.subtitle.id;
      }
    });
    await playerAvailableTracksSubscription?.cancel();
    playerAvailableTracksSubscription =
        mediaPlayer!.stream.tracks.listen((event) {
      playerAudioTracks = event.audio.toString();
      playerVideoTracks = event.video.toString();
      _updateEmbeddedTracks(event);
      unawaited(_selectDefaultEmbeddedTracks());
    });
    await playerAudioBitrateSubscription?.cancel();
    playerAudioBitrateSubscription =
        mediaPlayer!.stream.audioBitrate.listen((event) {
      playerAudioBitrate = event.toString();
    });
  }

  Future<void> cancelPlayerDebugInfoSubscription() async {
    await playerLogSubscription?.cancel();
    await playerWidthSubscription?.cancel();
    await playerHeightSubscription?.cancel();
    await playerVideoParamsSubscription?.cancel();
    await playerAudioParamsSubscription?.cancel();
    await playerPlaylistSubscription?.cancel();
    await playerTracksSubscription?.cancel();
    await playerAvailableTracksSubscription?.cancel();
    await playerAudioBitrateSubscription?.cancel();
  }

  Future<Player> createVideoController(Map<String, String> httpHeaders,
      {required PlayerMediaToken mediaToken,
      required PlayerLifecycleToken lifecycleToken,
      required PlaybackInitParams initParams,
      int offset = 0,
      String? subtitlePath}) async {
    final runtimeSettings = _runtimePreferences.load();
    anime4kPreference = runtimeSettings.anime4kPreference;
    hAenable = runtimeSettings.hardwareAccelerationEnabled;
    hardwareDecoder = runtimeSettings.hardwareDecoder;
    videoRenderer = runtimeSettings.videoRenderer;
    anime4kSupported = runtimeSettings.anime4kSupported;
    anime4kRuntimeState = anime4kPreference == Anime4kPreference.off
        ? Anime4kRuntimeState.off
        : anime4kSupported
            ? Anime4kRuntimeState.waitingForSize
            : Anime4kRuntimeState.incompatible;
    _anime4kCoordinator.reset();
    autoPlay = runtimeSettings.autoPlay;
    lowMemoryMode = runtimeSettings.lowMemoryMode;
    playerDebugMode = runtimeSettings.debugMode;
    colorProfile = _capabilities.isWindows
        ? runtimeSettings.colorProfile
        : PlayerColorProfile.automatic;
    effectiveColorProfile = PlayerColorProfile.automatic;
    colorProfileFallbackReason = null;
    _lastColorDiagnostic = null;

    final cachePolicy = CloudPlaybackCachePolicy.forTransport(
      initParams.transport,
      capabilities: _capabilities,
      lowMemoryMode: lowMemoryMode,
    );
    mediaPlayer = Player(
      configuration: PlayerConfiguration(
        bufferSize: cachePolicy.playerBufferSize ??
            (lowMemoryMode ? 15 * 1024 * 1024 : 1500 * 1024 * 1024),
        osc: false,
        libass: true,
        libassAndroidFont: 'assets/fonts/MiSans-Regular.ttf',
        libassAndroidFontName: 'MiSans',
        logLevel: MPVLogLevel.v,
      ),
    );
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
      await _disposePlayerResources();
      throw const _PlayerInitializationCancelled();
    }

    playerLog.clear();
    await setupPlayerDebugInfoSubscription();
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
      await _disposePlayerResources();
      throw const _PlayerInitializationCancelled();
    }

    var pp = mediaPlayer!.platform as NativePlayer;
    await _prepareSubtitleTrackState(pp);
    final colorDecision = await PlayerColorProfileApplier(
      pp.setProperty,
    ).apply(
      colorProfile,
      hdrOutputSupported: _capabilities.isWindows,
    );
    effectiveColorProfile = colorDecision.effective;
    colorProfileFallbackReason = colorDecision.fallbackReason;
    if (colorDecision.isFallback) {
      AppLogger().w(
        'PlayerColor: requested=${colorProfile.name} '
        'effective=${effectiveColorProfile.name} '
        'reason=${colorDecision.fallbackReason}',
      );
    } else {
      AppLogger().i(
        'PlayerColor: requested=${colorProfile.name} '
        'effective=${effectiveColorProfile.name}',
      );
    }
    // media-kit 默认启用硬盘作为双重缓存，这可以维持大缓存的前提下减轻内存压力
    // media-kit 内部硬盘缓存目录按照 Linux 配置，这导致该功能在其他平台上被损坏
    // 该设置可以在所有平台上正确启用双重缓存
    await pp.setProperty("demuxer-cache-dir", await Utils.getPlayerTempPath());
    await pp.setProperty("af", "scaletempo2=max-speed=8");
    if (_capabilities.isAndroid) {
      await pp.setProperty('demuxer-mkv-subtitle-preroll', 'yes');
      await pp.setProperty('demuxer-mkv-subtitle-preroll-secs', '10');
    }
    await _prepareAndroidAudioOutput(pp, trueHd: true);
    for (final property in cachePolicy.mpvProperties.entries) {
      await pp.setProperty(property.key, property.value);
    }
    // 设置 HTTP 代理
    final bool proxyEnable = runtimeSettings.proxyEnabled;
    if (shouldApplyPlayerProxy(
      proxyEnabled: proxyEnable,
      networkRoute: initParams.networkRoute,
    )) {
      final String proxyUrl = runtimeSettings.proxyUrl;
      final formattedProxy = ProxyUtils.getFormattedProxyUrl(proxyUrl);
      if (formattedProxy != null) {
        await pp.setProperty("http-proxy", formattedProxy);
        AppLogger().i('Player: HTTP 代理设置成功 $formattedProxy');
      }
    }

    await mediaPlayer!.setAudioTrack(
      AudioTrack.auto(),
    );

    videoController ??= VideoController(
      mediaPlayer!,
      configuration: VideoControllerConfiguration(
        vo: videoRenderer,
        enableHardwareAcceleration: hAenable,
        hwdec: hAenable ? hardwareDecoder : 'no',
      ),
    );
    AppLogger().i(
      'PlayerController: renderer=${videoRenderer ?? "platform-default"} '
      'hwdec=${hAenable ? hardwareDecoder : "no"}',
    );
    mediaPlayer!.setPlaylistMode(PlaylistMode.none);

    // error handle
    final bool showPlayerError = runtimeSettings.showPlayerError;
    await playerErrorSubscription?.cancel();
    playerErrorSubscription = mediaPlayer!.stream.error.listen((event) async {
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return;
      final errorStr = event.toString();
      final safeError = sanitizePlayerDiagnostic(errorStr);
      final decoderFailure = _decoderRecoveryPolicy.classify(errorStr);
      if (await _refreshExpiredCloudLink(
        errorStr,
        mediaToken,
        lifecycleToken,
        initParams,
      )) {
        return;
      }
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return;
      if (decoderFailure == PlayerDecoderFailureKind.video &&
          await _handleAndroidVideoDecoderError(
            errorStr,
            mediaToken,
            lifecycleToken,
          )) {
        return;
      }
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return;
      // TrueHD 解码失败时只切换已有的兼容音轨，不重建视频解码器。
      if (decoderFailure != PlayerDecoderFailureKind.video &&
          await _handleTrueHdPlaybackError(
            errorStr,
            mediaToken,
            lifecycleToken,
          )) {
        return;
      }
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return;
      if (!_decoderRecoveryPolicy.shouldReport(errorStr)) return;
      if (showPlayerError) {
        if (initParams.refreshCloudPlayback != null &&
            shouldRefreshCloudLink(errorStr)) {
          AppDialog.showToast(
            message: cloudPlaybackFailureMessage(
              initParams.cloudProviderName,
            ),
            duration: const Duration(seconds: 5),
            showActionButton: true,
          );
        } else if (errorStr.contains('Failed to open') && playerBuffering) {
          AppDialog.showToast(
              message: '加载失败, 请尝试更换其他视频来源', showActionButton: true);
        } else {
          AppDialog.showToast(
              message: '播放器内部错误，请稍后重试',
              duration: const Duration(seconds: 5),
              showActionButton: true);
        }
      }
      AppLogger().e(
        'PlayerController: player error for '
        '${sanitizeMediaDescription(initParams.videoUrl, isLocalPlayback: initParams.isLocalPlayback)} '
        'decoder=${decoderFailure.name} error=$safeError',
      );
    });

    await applySubtitleStyle(save: false);
    final playableUri = MediaUriUtils.toPlayableUri(
      videoUrl,
      isLocalPlayback: isLocalPlayback,
    );
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
      await _disposePlayerResources();
      throw const _PlayerInitializationCancelled();
    }
    await mediaPlayer!
        .open(
          Media(playableUri,
              start: Duration(seconds: offset), httpHeaders: httpHeaders),
          play: autoPlay,
        )
        .timeout(
          _PlayerController._playerOpenTimeout,
          onTimeout: () => throw TimeoutException(
            '播放器打开超时，请检查视频源或本地文件是否可播放',
            _PlayerController._playerOpenTimeout,
          ),
        );
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
      await _disposePlayerResources();
      throw const _PlayerInitializationCancelled();
    }
    if (subtitlePath != null && subtitlePath.isNotEmpty) {
      await loadExternalSubtitle(
        subtitlePath,
        displayName: initParams.subtitleDisplayName,
      );
    }
    await applySubtitleStyle(save: false);
    await _syncSubtitleDelayToPlayer();
    _scheduleAnime4kEvaluation();

    return mediaPlayer!;
  }

  void _logPlayerColorDiagnostic(VideoParams params) {
    final message = 'PlayerColor: input '
        'primaries=${params.primaries ?? "unknown"} '
        'transfer=${params.gamma ?? "unknown"} '
        'matrix=${params.colormatrix ?? "unknown"} '
        'levels=${params.colorlevels ?? "unknown"} '
        'signalPeak=${params.sigPeak?.toStringAsFixed(3) ?? "unknown"} '
        'light=${params.light ?? "unknown"} '
        'hwdec=${hAenable ? hardwareDecoder : "no"} '
        'profile=${effectiveColorProfile.name}';
    if (_lastColorDiagnostic == message) return;
    _lastColorDiagnostic = message;
    AppLogger().i(message);
  }

  Future<bool> _handleAndroidVideoDecoderError(
    String errorStr,
    PlayerMediaToken mediaToken,
    PlayerLifecycleToken lifecycleToken,
  ) async {
    final lower = errorStr.toLowerCase();
    final codecOpenFailed = lower.contains('could not open codec') ||
        lower.contains('failed to open codec') ||
        lower.contains('failed to initialize decoder');
    if (!_capabilities.isAndroid ||
        !hAenable ||
        _softwareVideoDecoderFallbackAttempted ||
        !codecOpenFailed ||
        !_isMediaOperationActive(mediaToken, lifecycleToken)) {
      return false;
    }
    final platform = mediaPlayer?.platform;
    if (platform is! NativePlayer) return false;

    _softwareVideoDecoderFallbackAttempted = true;
    try {
      await platform.setProperty('hwdec', 'no');
      await platform.command(const ['video-reload']);
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return true;
      hAenable = false;
      hardwareDecoder = 'no';
      AppLogger().w(
        'PlayerController: video decoder failed, reloaded with software decoding',
      );
      AppDialog.showToast(
        message: '硬件解码不兼容，已自动切换为软件解码',
        duration: const Duration(seconds: 3),
      );
      return true;
    } on Object catch (error, stackTrace) {
      AppLogger().e(
        'PlayerController: failed to reload video with software decoding',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> _handleTrueHdPlaybackError(
    String errorStr,
    PlayerMediaToken mediaToken,
    PlayerLifecycleToken lifecycleToken,
  ) async {
    if (!_isMediaOperationActive(mediaToken, lifecycleToken) ||
        !_isTrueHdRelatedPlaybackError(errorStr) ||
        _lastInitParams == null) {
      return false;
    }

    if (!_truehdAudioTrackFallbackAttempted) {
      _truehdAudioTrackFallbackAttempted = true;
      if (await _switchToCompatibleAudioTrackForTrueHd()) {
        return true;
      }
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return true;
      AppDialog.showToast(
        message: '当前播放器组件无法解码此音轨，请导出诊断日志',
        duration: const Duration(seconds: 5),
        showActionButton: true,
      );
    }
    return true;
  }

  bool _isTrueHdRelatedPlaybackError(String errorStr) {
    final player = mediaPlayer;
    return _trueHdFallbackPolicy.isRelatedError(
      errorStr,
      player?.state.tracks.audio ?? const <AudioTrack>[],
    );
  }

  Future<bool> _switchToCompatibleAudioTrackForTrueHd() async {
    if (!_embeddedTrackSelection.canAutomaticallySelectAudio) {
      AppDialog.showToast(message: '当前音轨播放失败，请手动选择其他音轨或导出诊断日志');
      return false;
    }
    final player = mediaPlayer;
    if (player == null) return false;
    final currentId = player.state.track.audio.id;
    final fallbackTrack = _trueHdFallbackPolicy.chooseFallback(
      player.state.tracks.audio,
      currentTrackId: currentId,
    );

    if (fallbackTrack == null) {
      AppLogger()
          .w('PlayerController: no compatible non-TrueHD audio track found');
      return false;
    }

    try {
      await _prepareAudioTrackOutput(player, fallbackTrack);
      await player.setAudioTrack(fallbackTrack);
      AppLogger().w(
          'PlayerController: switched from TrueHD to audio track ${fallbackTrack.id}');
      AppDialog.showToast(
        message: 'TrueHD 音轨播放失败，已切换到兼容音轨',
        duration: const Duration(seconds: 3),
      );
      return true;
    } catch (e) {
      AppLogger()
          .e('PlayerController: failed to switch TrueHD audio track', error: e);
      return false;
    }
  }

  Future<bool> loadExternalSubtitle(
    String? subtitlePath, {
    String? displayName,
  }) async {
    if (subtitlePath == null || subtitlePath.isEmpty) return false;
    if (!LocalSubtitleMatcher.isSupportedSubtitlePath(subtitlePath)) {
      return false;
    }
    final player = mediaPlayer;
    final params = _lastInitParams;
    if (player == null) return false;
    _subtitleTrackSelection.markManualSelection();
    final revision = ++_subtitleTrackRequestRevision;
    bool isCurrent() =>
        !_disposeRequested &&
        identical(player, mediaPlayer) &&
        identical(params, _lastInitParams) &&
        revision == _subtitleTrackRequestRevision;
    try {
      await _clearSubtitleTrackForSwitch();
      if (!isCurrent()) return false;
      await player.setSubtitleTrack(
        SubtitleTrack.uri(
          MediaUriUtils.toPlayableUri(
            subtitlePath,
            isLocalPlayback: true,
          ),
          title: displayName?.trim().isNotEmpty == true
              ? displayName!.trim()
              : p.basename(subtitlePath),
          language: 'auto',
        ),
      );
      if (!isCurrent()) return false;
      final pp = player.platform;
      if (pp is NativePlayer) {
        await _setFlutterSubtitleMode(pp);
      }
      if (!isCurrent()) return false;
      _setCurrentSubtitlePath(subtitlePath);
      selectedEmbeddedSubtitleTrackId = '';
      await applySubtitleStyle(save: false);
      if (!isCurrent()) return false;
      AppLogger().i('PlayerController: loaded subtitle $subtitlePath');
      return true;
    } catch (e) {
      AppLogger().w('PlayerController: failed to load subtitle $subtitlePath',
          error: e);
      return false;
    }
  }

  Future<bool> _disableSubtitleTrack({bool clearCurrentPath = false}) async {
    final player = mediaPlayer;
    final params = _lastInitParams;
    final revision = _subtitleTrackRequestRevision;
    if (player == null) return false;
    bool isCurrent() =>
        !_disposeRequested &&
        identical(player, mediaPlayer) &&
        identical(params, _lastInitParams) &&
        revision == _subtitleTrackRequestRevision;
    try {
      await player.setSubtitleTrack(SubtitleTrack.no());
    } catch (e) {
      AppLogger().w(
          'PlayerController: failed to disable media_kit subtitle track',
          error: e);
      return false;
    }
    if (!isCurrent()) return false;
    final pp = player.platform;
    if (pp is NativePlayer) {
      for (final property in [
        'sub-visibility',
        'secondary-sub-visibility',
        'sid',
        'secondary-sid'
      ]) {
        if (!isCurrent()) return false;
        await _trySetNativeSubtitleProperty(pp, property, 'no');
      }
    }
    if (!isCurrent()) return false;
    if (clearCurrentPath) {
      _setCurrentSubtitlePath('');
    }
    selectedEmbeddedSubtitleTrackId = '';
    return true;
  }

  Future<void> _clearSubtitleTrackForSwitch() async {
    if (!await _disableSubtitleTrack(clearCurrentPath: true)) {
      throw StateError('字幕关闭失败');
    }
  }

  Future<void> _prepareSubtitleTrackState(NativePlayer player) async {
    await _trySetNativeSubtitleProperty(player, 'sub-auto', 'no');
    await _trySetNativeSubtitleProperty(player, 'sid', 'no');
    await _trySetNativeSubtitleProperty(player, 'secondary-sid', 'no');
    await _setFlutterSubtitleMode(player);
  }

  Future<void> _prepareAndroidAudioOutput(
    NativePlayer player, {
    required bool trueHd,
  }) async {
    if (!_capabilities.isAndroid) return;
    await player.setProperty(
      'audio-channels',
      trueHd ? 'stereo' : 'auto-safe',
    );
    await player.setProperty(
      'ad-lavc-downmix',
      trueHd ? 'yes' : 'no',
    );
  }

  Future<void> _prepareAudioTrackOutput(
    Player player,
    AudioTrack track,
  ) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    await _prepareAndroidAudioOutput(
      platform,
      trueHd: _trueHdFallbackPolicy.isTrueHd(track),
    );
  }

  @override
  @action
  Future<bool> selectAudioTrack(String trackId, {bool manual = true}) async {
    final player = mediaPlayer;
    final params = _lastInitParams;
    final workKey = _trackPreferenceKey;
    if (player == null) return false;
    final track = player.state.tracks.audio
        .where((item) => item.id == trackId)
        .firstOrNull;
    if (track == null) return false;
    if (!manual && !_embeddedTrackSelection.canAutomaticallySelectAudio) {
      return false;
    }
    if (manual) _embeddedTrackSelection.markAudioSelectedManually();
    final revision = ++_audioTrackRequestRevision;
    bool isCurrent() =>
        !_disposeRequested &&
        identical(player, mediaPlayer) &&
        identical(params, _lastInitParams) &&
        revision == _audioTrackRequestRevision &&
        (manual || _embeddedTrackSelection.canAutomaticallySelectAudio);
    final previousId = selectedAudioTrackId;
    try {
      await _prepareAudioTrackOutput(player, track);
      if (!isCurrent()) return false;
      await player.setAudioTrack(track);
      if (!isCurrent()) return false;
      selectedAudioTrackId = track.id;
      if (manual) {
        await _rememberTrack(
            workKey,
            availableAudioTracks
                .where((value) => value.id == track.id)
                .firstOrNull);
      }
      AppLogger().i('PlayerController: selected audio track ${track.id}');
      return true;
    } catch (e) {
      if (!isCurrent()) return false;
      selectedAudioTrackId = previousId;
      AppLogger().e(
          'PlayerController: failed to select audio track ${track.id}',
          error: e);
      AppDialog.showToast(message: '音轨切换失败');
      return false;
    }
  }

  @override
  @action
  Future<bool> selectEmbeddedSubtitleTrack(String trackId,
      {bool manual = true}) async {
    final player = mediaPlayer;
    final params = _lastInitParams;
    final workKey = _trackPreferenceKey;
    final automaticRevision = _subtitleTrackSelection.beginAutomaticSelection();
    if (player == null) return false;
    final track = player.state.tracks.subtitle
        .where((item) => item.id == trackId && !item.uri && !item.data)
        .firstOrNull;
    if (track == null) return false;
    if (!manual &&
        !_subtitleTrackSelection
            .canApplyAutomaticSelection(automaticRevision)) {
      return false;
    }
    final previousId = selectedEmbeddedSubtitleTrackId;
    if (manual) {
      _subtitleTrackSelection.markManualSelection();
    }
    final revision = ++_subtitleTrackRequestRevision;
    bool isCurrent() =>
        !_disposeRequested &&
        identical(player, mediaPlayer) &&
        identical(params, _lastInitParams) &&
        revision == _subtitleTrackRequestRevision &&
        (manual ||
            _subtitleTrackSelection
                .canApplyAutomaticSelection(automaticRevision));
    try {
      await _clearSubtitleTrackForSwitch();
      if (!isCurrent()) return false;
      await player.setSubtitleTrack(track);
      if (!isCurrent()) return false;
      final platform = player.platform;
      if (platform is NativePlayer) {
        await _trySetNativeSubtitleProperty(platform, 'sub-visibility', 'yes');
        if (!isCurrent()) return false;
        await _trySetNativeSubtitleProperty(platform, 'secondary-sid', 'no');
        if (!isCurrent()) return false;
        await _trySetNativeSubtitleProperty(
          platform,
          'secondary-sub-visibility',
          'no',
        );
        if (!isCurrent()) return false;
        await _trySetNativeSubtitleProperty(platform, 'sid', track.id);
      }
      if (!isCurrent()) return false;
      selectedEmbeddedSubtitleTrackId = track.id;
      if (manual) {
        await _rememberTrack(
            workKey,
            availableEmbeddedSubtitleTracks
                .where((value) => value.id == track.id)
                .firstOrNull);
      }
      AppLogger().i('PlayerController: selected embedded subtitle ${track.id}');
      return true;
    } catch (e) {
      if (!isCurrent()) return false;
      selectedEmbeddedSubtitleTrackId = previousId;
      AppLogger().e(
        'PlayerController: failed to select embedded subtitle ${track.id}',
        error: e,
      );
      AppDialog.showToast(message: '字幕切换失败');
      return false;
    }
  }

  void _resetEmbeddedTrackState() {
    _audioTrackRequestRevision++;
    _subtitleTrackRequestRevision++;
    _embeddedTrackSelection.reset();
    _subtitleTrackSelection.reset();
    _trackLanguageConfirmationState.reset();
    trackLanguageConfirmationRevision++;
    availableAudioTracks.clear();
    availableEmbeddedSubtitleTracks.clear();
    pendingTrackLanguages.clear();
    selectedAudioTrackId = '';
    selectedEmbeddedSubtitleTrackId = '';
  }

  String _currentTrackLanguageMediaKey() {
    final stable = _lastInitParams?.stableMediaKey?.trim();
    if (stable != null && stable.isNotEmpty) return stable;
    final subtitleKey = _subtitleStorageKey?.trim();
    if (subtitleKey != null && subtitleKey.isNotEmpty) return subtitleKey;
    return videoUrl.trim();
  }

  String _fingerprintForTrack(String mediaKey, EmbeddedTrackInfo track) =>
      _embeddedTrackCoordinator.fingerprintForMedia(mediaKey, track);

  EmbeddedTrackInfo _applyStoredTrackLanguage(
    String mediaKey,
    EmbeddedTrackInfo track,
  ) {
    final choice = _embeddedTrackCoordinator.loadChoice(track);
    return choice == null ? track : track.withLanguage(choice);
  }

  PendingTrackLanguage? pendingTrackLanguageFor(EmbeddedTrackInfo track) {
    final fingerprint = _fingerprintForTrack(
      _currentTrackLanguageMediaKey(),
      track,
    );
    for (final pending in pendingTrackLanguages) {
      if (pending.fingerprint == fingerprint) return pending;
    }
    return null;
  }

  PendingTrackLanguage _pendingTrackLanguage(
    String mediaKey,
    EmbeddedTrackInfo track,
  ) =>
      PendingTrackLanguage(
        fingerprint: _fingerprintForTrack(mediaKey, track),
        type: track.type,
        trackId: track.id,
        codecLabel: track.originalCodec,
        title: track.originalTitle,
      );

  @override
  @action
  void _updateEmbeddedTracks(Tracks tracks) {
    final mediaKey = _currentTrackLanguageMediaKey();
    final audio = tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no' && !track.uri)
        .map(EmbeddedTrackInfo.fromAudio)
        .map((track) => _applyStoredTrackLanguage(mediaKey, track))
        .toList(growable: false);
    final subtitles = tracks.subtitle
        .where((track) =>
            track.id != 'auto' && track.id != 'no' && !track.uri && !track.data)
        .map(EmbeddedTrackInfo.fromSubtitle)
        .map((track) => _applyStoredTrackLanguage(mediaKey, track))
        .toList(growable: false);
    final pending = <PendingTrackLanguage>[
      for (final track in [...audio, ...subtitles])
        if (!track.isLanguageResolved) _pendingTrackLanguage(mediaKey, track),
    ];
    availableAudioTracks
      ..clear()
      ..addAll(audio);
    availableEmbeddedSubtitleTracks
      ..clear()
      ..addAll(subtitles);
    pendingTrackLanguages
      ..clear()
      ..addAll(pending);
    if (pending.isNotEmpty) {
      trackLanguageConfirmationRevision =
          _trackLanguageConfirmationState.begin(mediaKey, pending);
    }
    AppLogger().i(
      'PlayerController: detected ${availableAudioTracks.length} audio tracks and '
      '${availableEmbeddedSubtitleTracks.length} embedded subtitle tracks',
    );
  }

  void _applyConfirmedTrackLanguages(
    String mediaKey,
    Map<String, TrackLanguageChoice> choices,
  ) {
    EmbeddedTrackInfo resolve(EmbeddedTrackInfo track) {
      final choice = choices[_fingerprintForTrack(mediaKey, track)];
      return choice == null ? track : track.withLanguage(choice);
    }

    final audio = availableAudioTracks.map(resolve).toList(growable: false);
    final subtitles =
        availableEmbeddedSubtitleTracks.map(resolve).toList(growable: false);
    availableAudioTracks
      ..clear()
      ..addAll(audio);
    availableEmbeddedSubtitleTracks
      ..clear()
      ..addAll(subtitles);
  }

  @override
  @action
  Future<String?> confirmTrackLanguages(
    int revision,
    Map<String, TrackLanguageChoice> choices,
  ) async {
    final mediaKey = _currentTrackLanguageMediaKey();
    if (!_trackLanguageConfirmationState.canApply(revision, mediaKey)) {
      return null;
    }
    try {
      for (final pending in pendingTrackLanguages) {
        final choice = choices[pending.fingerprint];
        if (choice == null) return '请为每条轨道选择语言';
        await _trackLanguagePreferences.save(
          pending.fingerprint,
          choice.confirmedByUser(),
        );
        if (!_trackLanguageConfirmationState.canApply(revision, mediaKey)) {
          return null;
        }
      }
      _applyConfirmedTrackLanguages(mediaKey, choices);
      pendingTrackLanguages.clear();
      await _selectDefaultEmbeddedTracks();
      return null;
    } on Object {
      if (!_trackLanguageConfirmationState.canApply(revision, mediaKey)) {
        return null;
      }
      _applyConfirmedTrackLanguages(mediaKey, choices);
      pendingTrackLanguages.clear();
      await _selectDefaultEmbeddedTracks();
      return '语言设置未能保存，下次可能需要重新确认';
    }
  }

  @override
  @action
  Future<String?> confirmTrackLanguage(
    int revision,
    String fingerprint,
    TrackLanguageChoice choice,
  ) async {
    final mediaKey = _currentTrackLanguageMediaKey();
    if (!_trackLanguageConfirmationState.canApply(revision, mediaKey)) {
      return null;
    }
    final pending = pendingTrackLanguages
        .where((item) => item.fingerprint == fingerprint)
        .firstOrNull;
    if (pending == null) return null;
    try {
      await _trackLanguagePreferences.save(
        fingerprint,
        choice.confirmedByUser(),
      );
      if (!_trackLanguageConfirmationState.canApply(revision, mediaKey)) {
        return null;
      }
      _applyConfirmedTrackLanguages(mediaKey, {
        fingerprint: choice,
      });
      pendingTrackLanguages.remove(pending);
      return null;
    } on Object {
      if (!_trackLanguageConfirmationState.canApply(revision, mediaKey)) {
        return null;
      }
      _applyConfirmedTrackLanguages(mediaKey, {
        fingerprint: choice,
      });
      pendingTrackLanguages.remove(pending);
      return '语言设置未能保存，下次可能需要重新确认';
    }
  }

  Future<void> _selectDefaultEmbeddedTracks() async {
    final params = _lastInitParams;
    if (params != null && params.legacyTrackPreferenceKeys.isNotEmpty) {
      try {
        await _trackPreferences.migrate(
          params.trackPreferenceKey ?? '',
          params.legacyTrackPreferenceKeys,
        );
      } on Object catch (error) {
        AppLogger().w('PlayerController: track preference migration failed',
            error: error);
      }
      if (!identical(params, _lastInitParams) || _disposeRequested) return;
    }
    final shouldSelectAudio = _embeddedTrackSelection.beginAutomaticSelection(
      hasAudioTracks: availableAudioTracks.isNotEmpty,
    );
    final automaticSubtitleSelection =
        _subtitleTrackSelection.beginAutomaticSelection();
    final current = mediaPlayer?.state.track;
    final audio = selectTrackByPreferences(
      availableAudioTracks,
      series: _trackPreferences.load(
          _trackPreferenceKey, EmbeddedTrackType.audio,
          legacyWorkKeys: params?.legacyTrackPreferenceKeys ?? const []),
      global: globalTrackPreference(
          _runtimePreferences.settings.read<String>(
              SettingBoxKey.preferredAudioLanguage,
              defaultValue: 'zh'),
          EmbeddedTrackType.audio),
      defaultTrackId: current?.audio.id,
    );
    final seriesSubtitle = _trackPreferences.load(
        _trackPreferenceKey, EmbeddedTrackType.subtitle,
        legacyWorkKeys: params?.legacyTrackPreferenceKeys ?? const []);
    final globalSubtitle = globalTrackPreference(
        _runtimePreferences.settings.read<String>(
            SettingBoxKey.preferredSubtitleLanguage,
            defaultValue: 'zh-Hans'),
        EmbeddedTrackType.subtitle);
    final subtitle = selectTrackByPreferences(
      availableEmbeddedSubtitleTracks,
      series: seriesSubtitle,
      global: globalSubtitle,
      defaultTrackId: current?.subtitle.id,
    );
    if (shouldSelectAudio &&
        audio != null &&
        _embeddedTrackSelection.canAutomaticallySelectAudio) {
      await selectAudioTrack(audio.id, manual: false);
    }
    if (!_subtitleTrackSelection.canApplyAutomaticSelection(
          automaticSubtitleSelection,
        ) ||
        !identical(params, _lastInitParams) ||
        _disposeRequested) {
      return;
    }
    if (subtitle != null && currentSubtitlePath.isEmpty) {
      await selectEmbeddedSubtitleTrack(subtitle.id, manual: false);
    } else if (currentSubtitlePath.isEmpty &&
        (seriesSubtitle?.code == 'off' ||
            (seriesSubtitle == null && globalSubtitle?.code == 'off'))) {
      await _disableSubtitleTrack();
    }
    AppLogger().i(
      'PlayerController: automatic track selection audio=${audio?.id ?? "none"}, '
      'subtitle=${subtitle?.id ?? "off"}',
    );
  }

  Future<void> _setFlutterSubtitleMode(NativePlayer player) async {
    final useNativeSubtitleRendering = player.configuration.libass;
    await _trySetNativeSubtitleProperty(
      player,
      'sub-visibility',
      useNativeSubtitleRendering ? 'yes' : 'no',
    );
    await _trySetNativeSubtitleProperty(
      player,
      'secondary-sub-visibility',
      'no',
    );
    await _trySetNativeSubtitleProperty(player, 'secondary-sid', 'no');
  }

  Future<void> _trySetNativeSubtitleProperty(
    NativePlayer player,
    String property,
    String value,
  ) async {
    try {
      await player.setProperty(property, value);
    } catch (e) {
      AppLogger()
          .w('PlayerController: failed to set $property=$value', error: e);
    }
  }

  @override
  @action
  Future<void> refreshSubtitleCandidates() async {
    if (!isLocalPlayback || videoUrl.isEmpty) {
      subtitleCandidates.clear();
      return;
    }
    final candidates = await _localSubtitleMatcher.findAllForVideo(videoUrl);
    subtitleCandidates
      ..clear()
      ..addAll(candidates);
  }

  @override
  @action
  Future<bool> selectSubtitle(String subtitlePath) async {
    final loaded = await loadExternalSubtitle(subtitlePath);
    if (loaded && isLocalPlayback) {
      await refreshSubtitleCandidates();
    }
    return loaded;
  }

  @override
  @action
  Future<LocalSubtitleImportResult?> importSubtitle(
    String subtitlePath, {
    LocalSubtitleImportTarget target =
        LocalSubtitleImportTarget.subtitleDirectory,
  }) async {
    if (!isLocalPlayback || videoUrl.isEmpty) return null;
    final result = await _localSubtitleImporter.importForVideo(
      videoPath: videoUrl,
      subtitlePath: subtitlePath,
      target: target,
    );
    await refreshSubtitleCandidates();
    await loadExternalSubtitle(result.targetPath);
    return result;
  }

  @override
  @action
  Future<void> clearSubtitle() async {
    final workKey = _trackPreferenceKey;
    final player = mediaPlayer;
    final params = _lastInitParams;
    _subtitleTrackSelection.markManualSelection();
    final revision = ++_subtitleTrackRequestRevision;
    try {
      await _clearSubtitleTrackForSwitch();
      if (_disposeRequested ||
          !identical(player, mediaPlayer) ||
          !identical(params, _lastInitParams) ||
          revision != _subtitleTrackRequestRevision) {
        return;
      }
      try {
        await _trackPreferences.saveSubtitleOff(workKey);
      } on Object {
        AppDialog.showToast(message: '字幕已关闭，但跨集偏好保存失败');
      }
      AppLogger().i('PlayerController: subtitle disabled');
    } catch (e) {
      AppLogger().w('PlayerController: failed to disable subtitle', error: e);
    }
  }

  @override
  @action
  Future<bool> restoreLastSubtitle() async {
    final subtitlePath = lastSubtitlePath.trim();
    if (subtitlePath.isEmpty) return false;
    return selectSubtitle(subtitlePath);
  }

  void _setCurrentSubtitlePath(String value) {
    currentSubtitlePath = value;
    if (value.isNotEmpty) {
      lastSubtitlePath = value;
    }
  }

  @override
  @action
  Future<void> applySubtitleStyle({
    double? fontSize,
    int? colorValue,
    int? borderColorValue,
    double? borderSize,
    bool? shadowEnabled,
    double? shadowOffset,
    double? position,
    bool? forceStyle,
    bool save = true,
  }) async {
    subtitleFontSize =
        (fontSize ?? subtitleFontSize).clamp(18.0, 72.0).toDouble();
    subtitleColorValue = colorValue ?? subtitleColorValue;
    subtitleBorderColorValue = borderColorValue ?? subtitleBorderColorValue;
    subtitleBorderSize =
        (borderSize ?? subtitleBorderSize).clamp(0.0, 8.0).toDouble();
    subtitleShadowEnabled = shadowEnabled ?? subtitleShadowEnabled;
    subtitleShadowOffset =
        (shadowOffset ?? subtitleShadowOffset).clamp(0.0, 8.0).toDouble();
    subtitlePosition =
        (position ?? subtitlePosition).clamp(60.0, 100.0).toDouble();
    subtitleForceStyle = forceStyle ?? subtitleForceStyle;

    if (save) {
      await _subtitlePreferences.saveStyle(subtitleStyleSettings);
    }
    await _syncSubtitleStyleToPlayer();
  }

  @override
  @action
  Future<void> resetSubtitleStyle() {
    return applySubtitleStyle(
      fontSize: SubtitleStyleSettings.defaultFontSize,
      colorValue: SubtitleStyleSettings.defaultColorValue,
      borderColorValue: SubtitleStyleSettings.defaultBorderColorValue,
      borderSize: SubtitleStyleSettings.defaultBorderSize,
      shadowEnabled: SubtitleStyleSettings.defaultShadowEnabled,
      shadowOffset: SubtitleStyleSettings.defaultShadowOffset,
      position: SubtitleStyleSettings.defaultPosition,
      forceStyle: SubtitleStyleSettings.defaultForceStyle,
    );
  }

  @override
  @action
  Future<void> setSubtitleDelay(double seconds) async {
    final stepped = (seconds * 2).round() / 2;
    subtitleDelaySeconds = stepped.clamp(-30.0, 30.0).toDouble();
    await _syncSubtitleDelayToPlayer();
    await _saveSubtitleDelayForCurrentVideo();
  }

  @override
  @action
  Future<void> resetSubtitleDelay() => setSubtitleDelay(0.0);

  void _loadSubtitleDelayForCurrentVideo() {
    subtitleDelaySeconds = 0.0;
    if (!isLocalPlayback && _subtitleStorageKey == null) return;
    if (_subtitleDelayStorageKey.isEmpty) return;
    try {
      subtitleDelaySeconds = _subtitlePreferences.loadDelay(
        _subtitleDelayStorageKey,
      );
    } catch (e) {
      AppLogger()
          .w('PlayerController: failed to load subtitle delay', error: e);
    }
  }

  Future<void> _saveSubtitleDelayForCurrentVideo() async {
    if (!isLocalPlayback && _subtitleStorageKey == null) return;
    if (_subtitleDelayStorageKey.isEmpty) return;
    try {
      await _subtitlePreferences.saveDelay(
        _subtitleDelayStorageKey,
        subtitleDelaySeconds,
      );
    } catch (e) {
      AppLogger()
          .w('PlayerController: failed to save subtitle delay', error: e);
    }
  }

  String get _subtitleDelayStorageKey =>
      _subtitleStorageKey ?? videoUrl.trim().toLowerCase();

  Future<bool> _refreshExpiredCloudLink(
    String error,
    PlayerMediaToken mediaToken,
    PlayerLifecycleToken lifecycleToken,
    PlaybackInitParams params,
  ) async {
    final refresh = params.refreshCloudPlayback;
    if (!_isMediaOperationActive(mediaToken, lifecycleToken) ||
        refresh == null ||
        !_mediaOperations.tryBeginRefresh(mediaToken, error)) {
      return false;
    }
    final position = currentPosition;
    final wasPlaying = playing;
    final transaction = CloudPlaybackRefreshTransaction(
      previous: params,
      position: position,
      wasPlaying: wasPlaying,
    );
    try {
      final freshParams = await refresh();
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
        await _playbackLeaseCoordinator.reject(freshParams.lease);
        return true;
      }
      final refreshed = transaction.merge(freshParams);
      final refreshedToken = _mediaOperations.beginMedia(
        refreshed.stableMediaKey,
        preserveRefreshState: true,
      );
      await _playerInitLock.synchronized(
        () => _init(refreshed, refreshedToken, lifecycleToken),
      );
      if (transaction.shouldPauseAfterRefresh &&
          _isMediaOperationActive(refreshedToken, lifecycleToken)) {
        await pause();
      }
      return true;
    } on Object catch (refreshError, stackTrace) {
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return true;
      loading = false;
      isBuffering = false;
      AppLogger().e(
        'PlayerController: cloud playback link refresh failed',
        error: refreshError,
        stackTrace: stackTrace,
      );
      AppDialog.showToast(
        message: cloudPlaybackFailureMessage(params.cloudProviderName),
      );
      return true;
    } finally {
      _mediaOperations.finishRefresh(mediaToken);
    }
  }

  Future<void> _syncSubtitleDelayToPlayer() async {
    final pp = mediaPlayer?.platform;
    if (pp is! NativePlayer) return;
    try {
      await pp.setProperty(
          'sub-delay', subtitleDelaySeconds.toStringAsFixed(1));
    } catch (e) {
      AppLogger()
          .w('PlayerController: failed to sync subtitle delay', error: e);
    }
  }

  void _applyStoredSubtitleStyle() {
    final style = _subtitlePreferences.loadStyle();
    subtitleFontSize = style.fontSize;
    subtitleColorValue = style.colorValue;
    subtitleBorderColorValue = style.borderColorValue;
    subtitleBorderSize = style.borderSize;
    subtitleShadowEnabled = style.shadowEnabled;
    subtitleShadowOffset = style.shadowOffset;
    subtitlePosition = style.position;
    subtitleForceStyle = style.forceStyle;
  }

  Future<void> _syncSubtitleStyleToPlayer() async {
    final pp = mediaPlayer?.platform;
    if (pp is! NativePlayer) return;
    try {
      await pp.setProperty(
          'sub-font-size', subtitleFontSize.toStringAsFixed(0));
      await pp.setProperty('sub-color', _mpvColor(Color(subtitleColorValue)));
      await pp.setProperty(
        'sub-border-color',
        _mpvColor(Color(subtitleBorderColorValue)),
      );
      await pp.setProperty(
        'sub-border-size',
        subtitleBorderSize.toStringAsFixed(1),
      );
      await pp.setProperty(
        'sub-shadow-offset',
        subtitleShadowEnabled ? subtitleShadowOffset.toStringAsFixed(1) : '0',
      );
      await pp.setProperty('sub-pos', subtitlePosition.toStringAsFixed(0));
      await pp.setProperty(
        'sub-ass-override',
        subtitleForceStyle ? 'force' : 'no',
      );
      if (currentSubtitlePath.isNotEmpty) {
        await _setFlutterSubtitleMode(pp);
      }
    } catch (e) {
      AppLogger()
          .w('PlayerController: failed to sync subtitle style', error: e);
    }
  }

  String _mpvColor(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';
  }

  void updateAnime4kOutputSize({
    required Size logicalSize,
    required double devicePixelRatio,
  }) {
    final pixels = Size(
      logicalSize.width * devicePixelRatio,
      logicalSize.height * devicePixelRatio,
    );
    if (pixels == _anime4kOutputPixels) return;
    _anime4kOutputPixels = pixels;
    _scheduleAnime4kEvaluation();
  }

  void _scheduleAnime4kEvaluation() {
    _anime4kLayoutDebounce?.cancel();
    _anime4kLayoutDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_evaluateAnime4k()),
    );
  }

  @override
  @action
  Future<void> setAnime4kPreference(Anime4kPreference value) async {
    _anime4kLayoutDebounce?.cancel();
    _anime4kCoordinator.resetFailureLock();
    anime4kPreference = value;
    await _evaluateAnime4k();
  }

  @override
  @action
  void setAspectRatioType(int value) {
    if (aspectRatioType == value) return;
    aspectRatioType = value;
    _scheduleAnime4kEvaluation();
  }

  Future<void> _evaluateAnime4k() async {
    final player = mediaPlayer;
    if (anime4kSupported &&
        anime4kPreference != Anime4kPreference.off &&
        player?.platform is NativePlayer &&
        shadersController.shadersDirectory == null) {
      await shadersController.copyShadersToExternalDirectory();
      if (_disposeRequested || !identical(player, mediaPlayer)) return;
    }
    final decision = await _anime4kCoordinator.evaluateAndApply(
      Anime4kPolicyInput(
        preference: anime4kPreference,
        sourceWidth: playerWidth.toDouble(),
        sourceHeight: playerHeight.toDouble(),
        outputWidth: _anime4kOutputPixels.width,
        outputHeight: _anime4kOutputPixels.height,
        fit: switch (aspectRatioType) {
          2 => Anime4kFit.cover,
          3 => Anime4kFit.fill,
          _ => Anime4kFit.contain,
        },
        shaderSupported:
            anime4kShadersAvailable && mediaPlayer?.platform is NativePlayer,
      ),
    );
    runInAction(() => anime4kRuntimeState = decision.state);
  }

  Future<void> _executeAnime4kDecision(Anime4kDecision decision) async {
    final platform = mediaPlayer?.platform;
    if (platform is! NativePlayer) return;
    final stopwatch = Stopwatch()..start();
    var shaderCount = 0;
    await platform.waitForPlayerInitialization;
    await platform.waitForVideoControllerInitializationIfAttached;
    final executor = Anime4kShaderExecutor(command: platform.command);
    try {
      if (decision.action == Anime4kAction.clear) {
        await executor.apply(Anime4kAction.clear);
        return;
      }
      runInAction(() => anime4kRuntimeState = Anime4kRuntimeState.loading);
      final shadersDirectory = shadersController.shadersDirectory;
      final shaderPaths = resolveAnime4kShaderPaths(
        directoryPath: shadersDirectory?.path,
        action: decision.action,
      );
      if (shaderPaths == null) {
        throw StateError('Anime4K 着色器目录不可用');
      }
      shaderCount = shaderPaths.length;
      await executor.apply(
        decision.action,
        shaderPaths: shaderPaths,
      );
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        'Anime4K: disabled after load failure '
        'preference=${anime4kPreference.name} '
        'source=${playerWidth}x$playerHeight '
        'output=${_anime4kOutputPixels.width.round()}x${_anime4kOutputPixels.height.round()} '
        'shaders=$shaderCount elapsedMs=${stopwatch.elapsedMilliseconds}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      stopwatch.stop();
      AppLogger().i(
        'Anime4K: apply finished '
        'preference=${anime4kPreference.name} '
        'action=${decision.action.name} '
        'source=${playerWidth}x$playerHeight '
        'output=${_anime4kOutputPixels.width.round()}x${_anime4kOutputPixels.height.round()} '
        'shaders=$shaderCount elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
    }
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    this.playerSpeed = playerSpeed;
    final player = mediaPlayer;
    if (_disposeRequested || player == null) return;
    try {
      await player.setRate(playerSpeed);
    } catch (e) {
      AppLogger().e('PlayerController: failed to set playback speed', error: e);
    }
  }

  Future<void> setVolume(double value) async {
    value = value.clamp(0.0, 100.0);
    volume = value;
    try {
      final player = mediaPlayer;
      if (_disposeRequested || player == null) return;
      await player.setVolume(value);
    } catch (e) {
      AppLogger().d('设置音量失败', error: e);
    }
  }

  Future<void> playOrPause() async {
    final player = mediaPlayer;
    if (_disposeRequested || player == null) return;
    if (player.state.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration duration, {bool enableSync = true}) async {
    final player = mediaPlayer;
    if (_disposeRequested || player == null) return;
    currentPosition = duration;
    await player.seek(duration);
  }

  Future<void> pause({bool enableSync = true}) async {
    final player = mediaPlayer;
    if (_disposeRequested || player == null) return;
    await player.pause();
    playing = false;
  }

  Future<void> play({bool enableSync = true}) async {
    final player = mediaPlayer;
    if (_disposeRequested || player == null) return;
    await player.play();
    playing = true;
  }

  bool _isMediaOperationActive(
    PlayerMediaToken token,
    PlayerLifecycleToken lifecycleToken,
  ) =>
      !_disposeRequested &&
      _mediaOperations.isCurrent(token) &&
      _lifecycleOperations.isCurrent(lifecycleToken);

  Future<void> dispose() {
    final current = _disposeFuture;
    if (current != null) return current;
    _disposeRequested = true;
    _lifecycleOperations.invalidate();
    _mediaOperations.invalidate();
    AppLogger().i('PlayerController: resource disposal started');
    final future = _playerInitLock.synchronized(() async {
      await _disposePlayerResources();
      final clearLocalPlaybackCache = _clearLocalPlaybackCache;
      if (clearLocalPlaybackCache != null) {
        try {
          await clearLocalPlaybackCache();
        } on Object catch (error, stackTrace) {
          AppLogger().w(
            'PlayerController: failed to clear local playback cache',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      await _playbackLeaseCoordinator.close();
      _lastInitParams = null;
      AppLogger().i('PlayerController: resource disposal completed');
    });
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposePlayerResources() async {
    _anime4kLayoutDebounce?.cancel();
    _anime4kLayoutDebounce = null;
    _anime4kOutputPixels = Size.zero;
    _anime4kCoordinator.reset();
    runInAction(() => anime4kRuntimeState = Anime4kRuntimeState.off);

    final steps = <({String name, PlayerDisposeStep dispose})>[
      if (playerErrorSubscription case final subscription?)
        (name: 'error-subscription', dispose: subscription.cancel),
      if (playerLogSubscription case final subscription?)
        (name: 'log-subscription', dispose: subscription.cancel),
      if (playerWidthSubscription case final subscription?)
        (name: 'width-subscription', dispose: subscription.cancel),
      if (playerHeightSubscription case final subscription?)
        (name: 'height-subscription', dispose: subscription.cancel),
      if (playerVideoParamsSubscription case final subscription?)
        (name: 'video-params-subscription', dispose: subscription.cancel),
      if (playerAudioParamsSubscription case final subscription?)
        (name: 'audio-params-subscription', dispose: subscription.cancel),
      if (playerPlaylistSubscription case final subscription?)
        (name: 'playlist-subscription', dispose: subscription.cancel),
      if (playerTracksSubscription case final subscription?)
        (name: 'tracks-subscription', dispose: subscription.cancel),
      if (playerAvailableTracksSubscription case final subscription?)
        (name: 'available-tracks-subscription', dispose: subscription.cancel),
      if (playerAudioBitrateSubscription case final subscription?)
        (name: 'audio-bitrate-subscription', dispose: subscription.cancel),
      if (mediaPlayer case final player?)
        (name: 'player', dispose: player.dispose),
    ];

    playerErrorSubscription = null;
    playerLogSubscription = null;
    playerWidthSubscription = null;
    playerHeightSubscription = null;
    playerVideoParamsSubscription = null;
    playerAudioParamsSubscription = null;
    playerPlaylistSubscription = null;
    playerTracksSubscription = null;
    playerAvailableTracksSubscription = null;
    playerAudioBitrateSubscription = null;
    mediaPlayer = null;
    videoController = null;

    final failures = await _resourceDisposer.dispose(
      steps.map((step) => step.dispose),
    );
    for (final failure in failures) {
      AppLogger().w(
        'PlayerController: resource disposal failed '
        'step=${steps[failure.stepIndex].name}',
        error: failure.error,
        stackTrace: failure.stackTrace,
      );
    }
  }

  Future<void> stop() async {
    try {
      await mediaPlayer?.stop();
      loading = true;
    } catch (e) {
      AppLogger().d('停止播放失败', error: e);
    }
  }

  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async {
    final player = mediaPlayer;
    if (_disposeRequested || player == null) return null;
    return await player.screenshot(format: format);
  }

  void setButtonForwardTime(int time) {
    buttonSkipTime = time;
    unawaited(_runtimePreferences.saveButtonSkipTime(time));
  }

  void setArrowKeyForwardTime(int time) {
    arrowKeySkipTime = time;
    unawaited(_runtimePreferences.saveArrowKeySkipTime(time));
  }

  void lanunchExternalPlayer() async {
    if (referer.isNotEmpty) {
      AppDialog.showToast(message: '带鉴权请求头的视频暂不支持外部播放器');
      return;
    }
    if (await ExternalPlayer.launchURLWithMIME(videoUrl, 'video/mp4')) {
      AppDialog.dismiss<void>();
      AppDialog.showToast(message: '尝试唤起外部播放器');
    } else {
      AppDialog.showToast(message: '唤起外部播放器失败');
    }
  }
}
