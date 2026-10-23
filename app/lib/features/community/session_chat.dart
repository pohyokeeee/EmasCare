import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../app/preview_controller.dart';
import '../../data/backend_failure.dart';
import '../../data/chat_repository.dart';
import '../../models/backend_models.dart';
import '../../models/chat_models.dart';
import '../../models/session_models.dart';
import '../../models/preview_models.dart';
import '../../shared/design_system.dart';
import 'community_ui.dart';

bool sessionChatAvailable(SessionRequest request) =>
    request.helperId != null &&
    request.state != RequestState.requested &&
    request.state != RequestState.cancelled;

class SessionChatButton extends StatelessWidget {
  const SessionChatButton({super.key, required this.request});
  final SessionRequest request;

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    final repository = c.session?.repository;
    final participant = c.role == AppRole.elder || c.role == AppRole.helper;
    if (!participant || repository is! ChatRepository ||
        !sessionChatAvailable(request)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: EmasButton(
        label: c.t('Open session chat', 'Buka sembang sesi'),
        icon: Icons.chat_bubble_outline,
        secondary: true,
        onPressed: () => showEmasSheet(
          context,
          CommunitySheetGuard(
            token: scopeToken(c),
            child: SessionChatSheet(request: request),
          ),
        ),
      ),
    );
  }
}

class SessionChatSheet extends StatefulWidget {
  const SessionChatSheet({super.key, required this.request});
  final SessionRequest request;

  @override
  State<SessionChatSheet> createState() => _SessionChatSheetState();
}

class _SessionChatSheetState extends State<SessionChatSheet> {
  final _text = TextEditingController();
  List<SessionMessage> _messages = [];
  String? _error;
  bool _loading = true, _sending = false, _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  ChatRepository? get _repository {
    final c = PreviewScope.of(context);
    final repository = c.session?.repository;
    if (repository is ChatRepository) return repository as ChatRepository;
    return null;
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await repository.listSessionMessages(widget.request.id);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      final c = PreviewScope.of(context);
      setState(() {
        _loading = false;
        _error = BackendFailure.from(error).message(c.malay);
      });
    }
  }

  Future<void> _send() async {
    final value = _text.text.trim();
    if (value.isEmpty || value.length > 1000 || _sending) return;
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final message = await repository.sendSessionMessage(
        widget.request.id,
        value,
        'chat-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      _text.clear();
      setState(() {
        _messages = [..._messages, message];
        _sending = false;
      });
    } catch (error) {
      if (!mounted) return;
      final c = PreviewScope.of(context);
      setState(() {
        _sending = false;
        _error = BackendFailure.from(error).message(c.malay);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PreviewScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          c.t('Session chat', 'Sembang sesi'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          c.t(
            'Chat is available to the elder and assigned helper after assignment. Messages stay with this session.',
            'Sembang tersedia kepada warga emas dan pembantu yang ditetapkan selepas penugasan. Mesej kekal bersama sesi ini.',
          ),
        ),
        const SizedBox(height: 18),
        if (_loading)
          const LinearProgressIndicator()
        else if (_error != null)
          CommunityError(_error!, retry: _load)
        else if (_messages.isEmpty)
          PreviewEmpty(
            icon: Icons.chat_bubble_outline,
            title: c.t('No messages yet', 'Belum ada mesej'),
            description: c.t(
              'Send a short note before the session starts.',
              'Hantar nota ringkas sebelum sesi bermula.',
            ),
          )
        else
          for (final message in _messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Surface(
                color: message.senderUid == c.session?.profile?.uid
                    ? Palette.soft
                    : Palette.canvas,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.senderUid == c.session?.profile?.uid
                          ? c.t('You', 'Anda')
                          : message.senderRole == 'elder'
                          ? c.t('Elder', 'Warga emas')
                          : c.t('Helper', 'Pembantu'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(message.text),
                    const SizedBox(height: 4),
                    Text(
                      '${malaysiaDate(message.createdAt)} · ${malaysiaTime(message.createdAt)} MYT',
                      style: const TextStyle(color: Palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 14),
        TextField(
          controller: _text,
          maxLength: 1000,
          minLines: 2,
          maxLines: 4,
          enabled: !_sending,
          decoration: InputDecoration(
            labelText: c.t('Message', 'Mesej'),
            hintText: c.t('Write a short message', 'Tulis mesej ringkas'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        EmasButton(
          label: _sending
              ? c.t('Sending…', 'Menghantar…')
              : c.t('Send message', 'Hantar mesej'),
          icon: Icons.send_outlined,
          onPressed: _sending ? null : _send,
        ),
        TextButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(c.t('Refresh messages', 'Muat semula mesej')),
        ),
      ],
    );
  }
}
