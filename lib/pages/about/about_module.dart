import 'package:flutter/material.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:kanyingyin/pages/about/about_page.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/logs/logs_page.dart';

class AboutModule extends Module {
  @override
  void binds(i) {}

  @override
  void routes(r) {
    r.child("/", child: (_) => const AboutPage());
    r.child("/logs", child: (_) => const LogsPage());
    r.child(
      "/license",
      child: (_) => const LicensePage(
        applicationName: '看影音',
        applicationVersion: AppVersion.current,
        applicationLegalese: '开源许可证',
      ),
    );
  }
}
