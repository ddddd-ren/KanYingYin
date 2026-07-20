import 'package:kanyingyin/services/cloud/cloud_cache_directories.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_service.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_remote_reader.dart';

typedef QuarkRangeRelayStarter = Future<QuarkRangeRelayPlayback> Function({
  required QuarkRemoteResource resource,
  required QuarkRemoteResourceRefresher refreshResource,
});

typedef QuarkRangeRelayPlayback = CloudRangeRelayPlayback;

class QuarkRangeRelayService {
  QuarkRangeRelayService({
    CloudCacheRootProvider? cacheRootProvider,
  }) : _relayService = CloudRangeRelayService(
          cacheRootProvider: cacheRootProvider,
        );

  final CloudRangeRelayService _relayService;

  Future<QuarkRangeRelayPlayback> start({
    required QuarkRemoteResource resource,
    required QuarkRemoteResourceRefresher refreshResource,
  }) =>
      _relayService.start(
        reader: QuarkRangeRemoteReader(
          resource: resource,
          refreshResource: refreshResource,
        ),
        providerKey: 'quark',
        providerName: '夸克',
      );

  Future<void> close() => _relayService.close();
}
