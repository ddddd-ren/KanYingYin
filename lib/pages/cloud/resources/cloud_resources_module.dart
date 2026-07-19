import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_page.dart';

class CloudResourcesModule extends Module {
  @override
  void routes(r) {
    r.child('/', child: (_) => const CloudResourcesPage());
  }
}
