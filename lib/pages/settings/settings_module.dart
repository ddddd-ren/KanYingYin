import 'package:kanyingyin/pages/about/about_module.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/history/history_module.dart';
import 'package:kanyingyin/pages/settings/interface_settings.dart';
import 'package:kanyingyin/pages/settings/theme_settings_page.dart';
import 'package:kanyingyin/pages/settings/player_settings.dart';
import 'package:kanyingyin/pages/settings/displaymode_settings.dart';
import 'package:kanyingyin/pages/settings/decoder_settings.dart';
import 'package:kanyingyin/pages/settings/renderer_settings.dart';
import 'package:kanyingyin/pages/settings/super_resolution_settings.dart';
import 'package:kanyingyin/pages/settings/keyboard_settings.dart';
import 'package:kanyingyin/pages/settings/tmdb_settings.dart';
import 'package:kanyingyin/pages/settings/cloud_sources_settings.dart';
import 'package:kanyingyin/pages/cloud/openlist_source_editor.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';

class SettingsModule extends Module {
  @override
  void routes(r) {
    r.child("/theme", child: (_) => const ThemeSettingsPage());
    r.child(
      "/theme/display",
      child: (_) => const SetDisplayMode(),
    );
    r.child("/keyboard", child: (_) => const KeyboardSettingsPage());
    r.child("/player", child: (_) => const PlayerSettingsPage());
    r.child("/player/decoder", child: (_) => const DecoderSettings());
    r.child("/player/renderer", child: (_) => const RendererSettings());
    r.child("/interface", child: (_) => const InterfaceSettingsPage());
    r.child("/player/super", child: (_) => const SuperResolutionSettings());
    r.module("/about", module: AboutModule());
    r.module("/history", module: HistoryModule());
    r.child("/tmdb", child: (_) => const TmdbSettingsPage());
    r.child(
      "/cloud-sources",
      child: (_) => CloudSourcesSettingsPage(
        controller: Modular.get<CloudLibraryController>(),
        onSourceDeleted: Modular.get<LocalController>().reloadCloudLibraryIndex,
        onSourceScanned:
            Modular.get<LocalController>().revealCloudLibrarySource,
      ),
    );
    r.child(
      "/cloud-sources/edit",
      child: (_) => OpenListSourceEditorPage(
        controller: Modular.get<CloudLibraryController>(),
        source: r.args.data is CloudSource ? r.args.data as CloudSource : null,
      ),
    );
  }
}
