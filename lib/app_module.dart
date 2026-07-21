import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/index_module.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

class AppModule extends Module {
  AppModule({required this.tmdbCredentialManager});

  final TmdbCredentialManager tmdbCredentialManager;

  @override
  void binds(i) {}

  @override
  void routes(r) {
    r.module(
      "/",
      module: IndexModule(tmdbCredentialManager: tmdbCredentialManager),
    );
  }
}
