import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/preview_controller.dart';
import '../../models/backend_models.dart';
import '../../models/preview_models.dart';
import '../../platform/browser_support.dart';
import '../../shared/design_system.dart';
import '../community/session_ui.dart';

class VoiceBookingView extends StatefulWidget {
  const VoiceBookingView({super.key, required this.onManual});
  final VoidCallback onManual;
  @override
  State<VoiceBookingView> createState() => _VoiceBookingViewState();
}

class _VoiceBookingViewState extends State<VoiceBookingView> {
  final text = TextEditingController();
  Json? audio;
  String? deviceMessage;
  String intent = '';
  bool recording = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (intent.isEmpty) {
      intent = PreviewScope.of(context).sessions!.nextIntent();
    }
  }

  @override
  void dispose() {
    text.dispose();
    unawaited(voiceAction({'action': 'cancel'}));
    super.dispose();
  }

  void done() {
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      final c = PreviewScope.of(context);
      Navigator.pop(context);
      c.navigate(destination: Destination.companion);
    }
  }

  Future<void> record() async {
    setState(() {
      recording = true;
      audio = null;
      deviceMessage = null;
    });
    final result = await voiceAction({'action': 'record'});
    if (!mounted) return;
    setState(() {
      recording = false;
      if (result['error'] != true) {
        audio = {
          'type': 'audio',
          'mimeType': result['mimeType'],
          'base64': result['base64'],
        };
      } else {
        deviceMessage = result['message'] as String?;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context), w = c.coordination!, result = w.voice;
    final action = 'create:voice-$intent',
        pending = c.sessions!.actions[action];
    final busy = w.voiceBusy || pending?.busy == true || recording;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c.t('Tell us what would help.', 'Beritahu bantuan yang diperlukan.'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 14),
        Text(
          c.t(
            'Prepare draft sends your text or recording to the configured voice provider. Recording stops after 30 seconds. Nothing is booked until you confirm. Manual booking is always available.',
            'Sediakan draf menghantar teks atau rakaman anda kepada penyedia suara yang dikonfigurasi. Rakaman berhenti selepas 30 saat. Tiada tempahan sehingga anda mengesahkan. Tempahan manual sentiasa tersedia.',
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: text,
          maxLength: 1000,
          maxLines: 3,
          enabled: !busy && pending == null,
          decoration: InputDecoration(
            labelText: c.t(
              'What would you like to do?',
              'Apa yang anda ingin lakukan?',
            ),
          ),
          onChanged: (_) {
            w.clearVoice();
            setState(() => audio = null);
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: busy || pending != null ? null : record,
              icon: const Icon(Icons.mic_none),
              label: Text(
                c.t('Record up to 30 seconds', 'Rakam sehingga 30 saat'),
              ),
            ),
            if (recording)
              OutlinedButton(
                onPressed: () => voiceAction({'action': 'stop'}),
                child: Text(c.t('Stop recording', 'Hentikan rakaman')),
              ),
          ],
        ),
        if (recording)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.t(
                'Recording… Stop when you are ready.',
                'Merakam… Hentikan apabila sedia.',
              ),
            ),
          ),
        if (audio != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.t(
                'Recording ready. Prepare the draft to submit it.',
                'Rakaman sedia. Sediakan draf untuk menghantarnya.',
              ),
            ),
          ),
        if (deviceMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(deviceMessage!),
          ),
        const SizedBox(height: 16),
        EmasButton(
          key: const ValueKey('parse-voice-booking'),
          label: c.t('Prepare draft', 'Sediakan draf'),
          onPressed: busy || pending != null
              ? null
              : () async {
                  if (audio == null && text.text.trim().isEmpty) {
                    setState(
                      () => deviceMessage = c.t(
                        'Enter a request or record a short message.',
                        'Masukkan permintaan atau rakam mesej ringkas.',
                      ),
                    );
                    return;
                  }
                  await w.parseVoice(
                    audio ?? {'type': 'text', 'text': text.text.trim()},
                    c.malay ? 'bm' : 'en',
                  );
                },
        ),
        if (w.voiceBusy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (w.errors['voice'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Surface(
              color: Palette.sand,
              child: Text(w.errors['voice']!.message(c.malay)),
            ),
          ),
        if (result != null) ...[
          const SizedBox(height: 20),
          Surface(
            color: Palette.soft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.t('Review your request', 'Semak permintaan anda'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(result.transcript),
                const SizedBox(height: 12),
                if (result.readBackText != null) Text(result.readBackText!),
                if (result.clarification != null) Text(result.clarification!),
                if (!result.canConfirm)
                  Text(
                    c.t(
                      'Add the missing details and prepare another draft, or use the manual form.',
                      'Tambah butiran yang belum lengkap dan sediakan draf lain, atau gunakan borang manual.',
                    ),
                  ),
                if (result.readBackText != null)
                  TextButton.icon(
                    icon: const Icon(Icons.volume_up_outlined),
                    label: Text(c.t('Read this aloud', 'Bacakan ini')),
                    onPressed: () async {
                      final read = await voiceAction({
                        'action': 'speak',
                        'text': result.readBackText,
                        'locale': c.malay ? 'bm' : 'en',
                      });
                      if (mounted) {
                        setState(
                          () => deviceMessage = read['message'] as String?,
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
          if (result.canConfirm) ...[
            const SizedBox(height: 16),
            EmasButton(
              key: const ValueKey('confirm-voice-request'),
              label: c.t(
                'Confirm booking request',
                'Sahkan permintaan tempahan',
              ),
              onPressed: pending != null
                  ? null
                  : () async {
                      if (await c.sessions!.run(
                        action,
                        'create',
                        result.draft!,
                      )) {
                        done();
                      }
                    },
            ),
            PendingSessionAction(action, onSuccess: done),
          ],
        ],
        const SizedBox(height: 18),
        EmasButton(
          key: const ValueKey('voice-manual-fallback'),
          label: c.t('Use manual booking', 'Gunakan tempahan manual'),
          secondary: true,
          onPressed: busy || pending != null ? null : widget.onManual,
        ),
      ],
    );
  }
}
