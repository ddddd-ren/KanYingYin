import 'package:kanyingyin/app/startup_landing.dart';
import 'package:kanyingyin/pages/local/local_page.dart';
import 'package:flutter_modular/flutter_modular.dart';

class LocalModule extends Module {
  @override
  void routes(r) {
    r.child("/", child: (_) => const StartupLanding(child: LocalPage()));
  }
}
