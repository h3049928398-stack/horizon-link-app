import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Register notices for vendored code and embedded font derivatives.
void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'forza-wheel-leds',
    ], await rootBundle.loadString('assets/licenses/forza-wheel-leds-MIT.txt'));
    for (final font in [
      ('Noto Sans SC', 'NotoSansSC-OFL.txt'),
      ('Barlow Condensed', 'BarlowCondensed-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        font.$1,
      ], await rootBundle.loadString('assets/licenses/${font.$2}'));
    }
    yield LicenseEntryWithLineBreaks(
      ['FH6 Scenic Navigator'],
      'Project: https://github.com/atikhobaev/fh6-scenic-navigator\n\n'
      'Acknowledgement: WVAN extraction/parser and graph compilation tooling, '
      'world-coordinate projection calibration reference, and selected bundled '
      'community place records.\n\n'
      'The following MIT license applies to the upstream software.\n\n'
      '${await rootBundle.loadString('assets/licenses/fh6-scenic-navigator-MIT.txt')}',
    );
  });
}
