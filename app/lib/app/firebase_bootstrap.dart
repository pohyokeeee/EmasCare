import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import '../data/backend_repository.dart';
import '../data/firebase_backend_repository.dart';
import '../shared/design_system.dart';
import 'emas_app.dart';

class FirebaseBootstrap extends StatefulWidget {
  const FirebaseBootstrap({super.key});
  @override
  State<FirebaseBootstrap> createState() => _FirebaseBootstrapState();
}

class _FirebaseBootstrapState extends State<FirebaseBootstrap> {
  SemanticsHandle? _semantics;
  @override
  void initState() {
    super.initState();
    if (kIsWeb) _semantics = WidgetsBinding.instance.ensureSemantics();
  }

  @override
  void dispose() {
    _semantics?.dispose();
    super.dispose();
  }

  late final Future<BackendRepository> _connection = _connect();
  Future<BackendRepository> _connect() async {
    try {
      return await FirebaseBackendRepository.connect();
    } catch (error) {
      debugPrint('Local Firebase initialization failed: $error');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BackendRepository>(
    future: _connection,
    builder: (context, snapshot) {
      if (snapshot.hasData) return EmasCareApp(backend: snapshot.data);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: emasTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Local Firebase setup could not start. Open this app at http://127.0.0.1:8090 and reload.',
                        ),
                        const SizedBox(height: 18),
                        TextButton(
                          onPressed: () => runApp(const EmasCareApp()),
                          child: const Text(
                            'Open design preview · sample data',
                          ),
                        ),
                      ],
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text('Starting EmasCare local demo…'),
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );
}
