import 'dart:convert';
import 'dart:js_interop';

@JS('emasPreview.action')
external JSPromise<JSString> _action(JSString action);

Future<Map<String, dynamic>> browserAction(String action) async =>
    jsonDecode((await _action(action.toJS).toDart).toDart)
        as Map<String, dynamic>;
