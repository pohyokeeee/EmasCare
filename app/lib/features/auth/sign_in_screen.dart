import 'package:flutter/material.dart';
import '../../app/preview_controller.dart';
import '../../shared/design_system.dart';
import '../../shared/park_art.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final s = c.session!;
    void submit() {
      if (_form.currentState!.validate()) s.signIn(_email.text, _password.text);
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'EmasCare',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: c.toggleLanguage,
                        child: Text(c.malay ? 'EN' : 'BM'),
                      ),
                      IconButton(
                        tooltip: c.t('Larger text', 'Teks lebih besar'),
                        onPressed: () => c.setPreferences(text: !c.largeText),
                        icon: const Icon(Icons.text_fields),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                    child: SizedBox(height: 155, child: ParkArt()),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    c.t(
                      'A little company.\nA calmer day.',
                      'Sedikit teman.\nHari lebih tenang.',
                    ),
                    style: const TextStyle(
                      fontSize: 31,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    c.t(
                      'Sign in to your local EmasCare account.',
                      'Log masuk ke akaun EmasCare setempat anda.',
                    ),
                  ),
                  const SizedBox(height: 22),
                  Surface(
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Pill('LOCAL DEMO · Firebase emulators'),
                          const SizedBox(height: 20),
                          if (s.loading) ...[
                            const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              c.t(
                                'Checking your server profile…',
                                'Menyemak profil pelayan anda…',
                              ),
                            ),
                          ] else ...[
                            TextFormField(
                              controller: _email,
                              enabled: !s.authBusy,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.username],
                              decoration: InputDecoration(
                                labelText: c.t('Email', 'E-mel'),
                              ),
                              validator: (v) => v?.contains('@') == true
                                  ? null
                                  : c.t(
                                      'Enter your email.',
                                      'Masukkan e-mel anda.',
                                    ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _password,
                              enabled: !s.authBusy,
                              obscureText: true,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: c.t('Password', 'Kata laluan'),
                              ),
                              onFieldSubmitted: (_) {
                                if (!s.authBusy) submit();
                              },
                              validator: (v) => v?.isNotEmpty == true
                                  ? null
                                  : c.t(
                                      'Enter your password.',
                                      'Masukkan kata laluan.',
                                    ),
                            ),
                            const SizedBox(height: 22),
                            EmasButton(
                              label: s.authBusy
                                  ? c.t('Signing in…', 'Sedang log masuk…')
                                  : c.t('Sign in', 'Log masuk'),
                              onPressed: s.authBusy ? null : submit,
                            ),
                          ],
                          if (s.authError != null) ...[
                            const SizedBox(height: 14),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                s.authError!.message(c.malay),
                                style: const TextStyle(color: Palette.gold),
                              ),
                            ),
                            TextButton(
                              onPressed: s.retryProfile,
                              child: Text(
                                c.t('Retry profile', 'Cuba semula profil'),
                              ),
                            ),
                          ],
                          if (!s.authBusy)
                            TextButton(
                              onPressed: () => s.signOut(enterPreview: true),
                              child: Text(
                                c.t(
                                  'Explore the design preview',
                                  'Teroka pratonton reka bentuk',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    c.t(
                      'Local accounts only. Your role is loaded from the server. Preview mode uses sample data.',
                      'Akaun setempat sahaja. Peranan dimuatkan dari pelayan. Pratonton menggunakan data contoh.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
