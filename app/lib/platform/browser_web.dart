import 'dart:convert';
import 'dart:js_interop';

@JS('emasPreview.action')
external JSPromise<JSString> _action(JSString action);
@JS('emasVoice.action')
external JSPromise<JSString> _voice(JSString command);

Future<Map<String, dynamic>> voiceAction(Map<String, dynamic> command) async =>
    jsonDecode((await _voice(jsonEncode(command).toJS).toDart).toDart)
        as Map<String, dynamic>;

Future<Map<String, dynamic>> browserAction(String action) async =>
    jsonDecode((await _action(action.toJS).toDart).toDart)
        as Map<String, dynamic>;
