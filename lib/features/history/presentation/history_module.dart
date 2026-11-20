import 'package:kanyingyin/app/startup_landing.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/history/presentation/history_page.dart';

class HistoryModule extends Module {
  @override
  void routes(r) {
    r.child('/', child: (_) => const StartupLanding(child: HistoryPage()));
  }
}
