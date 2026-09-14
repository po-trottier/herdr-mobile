import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/models/message.dart';
import 'package:herdr_mobile/models/messages/host_info.dart';

void main() {
  const palette = <String, dynamic>{
    'name': 'vesper',
    'accent': '#8A9A7B',
    'panel_bg': '#101010',
    'surface0': '#1C1C1C',
    'surface1': '#282828',
    'surface_dim': '#101010',
    'overlay0': '#505050',
    'overlay1': '#606060',
    'text': '#D0D0D0',
    'subtext0': '#909090',
    'mauve': '#8A9A7B',
    'green': '#8A9A7B',
    'yellow': '#D0A050',
    'red': '#C05050',
    'blue': '#6080A0',
    'teal': '#70A0A0',
    'peach': '#D08050',
  };
  test('host_theme preserves the wire palette (R-03-131)', () {
    final message = messageFromTypeAndPayload('host_theme', {'theme': palette});
    expect(message, isA<MessageHostTheme>());
    expect(message.typeName, 'host_theme');
    expect(message.payloadJson, {'theme': palette});
    final theme = (message as MessageHostTheme).payload.theme;
    expect(theme.surfaceDim, '#101010');
    expect(theme.panelBg, '#101010');
  });

  test('host_info accepts and omits an absent palette (R-03-131)', () {
    const fields = <String, dynamic>{
      'protocol': 1,
      'host_id': 'test-host',
      'host_name': 'test',
      'herdr_version': 'test',
      'herdr_protocol': 22,
      'paired': true,
    };
    final absent = HostInfo.fromJson(fields);
    expect(absent.theme, isNull);
    expect(absent.toJson(), fields);
    final present = HostInfo.fromJson({...fields, 'theme': palette});
    expect(present.theme?.surfaceDim, '#101010');
    expect(present.toJson(), {...fields, 'theme': palette});
  });
}
