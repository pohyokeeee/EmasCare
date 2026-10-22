Future<Map<String, dynamic>> browserAction(String action) async => {
  'secure': false,
  'microphone': false,
  'speech': false,
  'permission': 'unavailable',
  'message': 'Browser only',
};

Future<Map<String, dynamic>> voiceAction(Map<String, dynamic> command) async =>
    {
      'error': true,
      'message': 'Audio recording is unavailable. Use text or manual booking.',
    };
