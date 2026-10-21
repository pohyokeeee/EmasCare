import 'package:flutter/widgets.dart';
import 'app/firebase_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FirebaseBootstrap());
}
