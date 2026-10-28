import 'dart:io';

/// Joins the ESP32 access point from Windows so the test screen can open it.
class IntercomTestWifi {
  const IntercomTestWifi._();

  static final RegExp _safeSsid = RegExp(r'^[A-Za-z0-9 _.\-]{1,32}$');

  static Future<String?> join({
    required String ssid,
    required String password,
  }) async {
    if (!Platform.isWindows) {
      return 'Joining the ESP Wi-Fi from the app works on Windows.';
    }
    final String name = ssid.trim();
    if (!_safeSsid.hasMatch(name)) {
      return 'Use a Wi-Fi name of letters, numbers, spaces, dot, or dash.';
    }
    if (password.length < 8 || password.length > 63) {
      return 'The ESP password must be 8 to 63 characters.';
    }
    final File profile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}FuelPointIntercom.xml',
    );
    try {
      await profile.writeAsString(_profileXml(name, password));
      final ProcessResult added = await _netsh(
        'netsh wlan add profile filename="${profile.path}" user=current',
      );
      if (added.exitCode != 0) {
        return _netshError('Could not save that Wi-Fi profile.', added);
      }
      final ProcessResult connected = await _netsh(
        'netsh wlan connect name="$name"',
      );
      if (connected.exitCode != 0) {
        return _netshError('Could not join $name.', connected);
      }
      return null;
    } catch (error) {
      return 'Could not join $name. $error';
    } finally {
      try {
        if (profile.existsSync()) {
          profile.deleteSync();
        }
      } catch (_) {}
    }
  }

  static Future<bool> hasSubnet(String host) async {
    final List<String> parts = host.trim().split('.');
    if (parts.length != 4) {
      return false;
    }
    final String prefix = '${parts[0]}.${parts[1]}.${parts[2]}.';
    try {
      final List<NetworkInterface> ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final NetworkInterface iface in ifaces) {
        for (final InternetAddress address in iface.addresses) {
          if (address.address.startsWith(prefix) && address.address != host) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  static Future<ProcessResult> _netsh(String command) {
    return Process.run('cmd', <String>['/c', command]);
  }

  static String _netshError(String lead, ProcessResult result) {
    final String detail = '${result.stdout}\n${result.stderr}'.trim();
    if (detail.isEmpty) {
      return lead;
    }
    return '$lead $detail';
  }

  static String _profileXml(String ssid, String password) {
    final String name = _xml(ssid);
    return '''
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$name</name>
  <SSIDConfig>
    <SSID>
      <hex>${_hex(ssid)}</hex>
      <name>$name</name>
    </SSID>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>WPA2PSK</authentication>
        <encryption>AES</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
      <sharedKey>
        <keyType>passPhrase</keyType>
        <protected>false</protected>
        <keyMaterial>${_xml(password)}</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
  <MacRandomization xmlns="http://www.microsoft.com/networking/WLAN/profile/v3">
    <enableRandomization>false</enableRandomization>
  </MacRandomization>
</WLANProfile>
''';
  }

  static String _xml(String raw) {
    return raw
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String _hex(String raw) {
    final StringBuffer buffer = StringBuffer();
    for (final int byte in raw.codeUnits) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
