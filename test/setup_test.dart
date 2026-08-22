import 'package:test/test.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
    test('pins release packaging dependencies', () {
      expect(
        setup.flutterDistributorGitRef,
        'd61d99fb245c72f4678609ccbff1766827fcf718',
      );
      expect(setup.appdmgVersion, '0.6.6');
    });

    test('parses -v as verbose mode', () {
      final results = setup.createSetupArgParser().parse(['android', '-v']);

      expect(results['verbose'], isTrue);
      expect(results.rest, ['android']);
    });

    test('accepts dev application environment', () {
      final results = setup.createSetupArgParser().parse([
        'android',
        '--env',
        'dev',
      ]);

      expect(results['env'], 'dev');
    });

    test('Flutter build environment does not depend on Core SHA256', () {
      expect(setup.createBuildEnvironment('dev'), {'APP_ENV': 'dev'});
    });

    test('includes the commercial release repository when supplied', () {
      expect(
        setup.createBuildEnvironment(
          'stable',
          releaseRepository: 'ai68/flclash-plus',
          paymentHosts: 'stripe.com,paypal.com',
        ),
        {
          'APP_ENV': 'stable',
          'FLCLASH_PLUS_RELEASE_REPOSITORY': 'ai68/flclash-plus',
          'AI68_PAYMENT_HOSTS': 'stripe.com,paypal.com',
        },
      );
    });

    test('omits verbose from flutter build args by default', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        targets: 'apk',
        verbose: false,
      );

      expect(args, ['dart-define-from-file=env.json', 'split-per-abi']);
    });

    test('adds verbose to flutter build args with -v', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        targets: 'apk',
        verbose: true,
      );

      expect(args, [
        'verbose',
        'dart-define-from-file=env.json',
        'split-per-abi',
      ]);
    });

    test('omits split-per-abi for Android app bundles', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        targets: 'aab',
        verbose: false,
      );

      expect(args, ['dart-define-from-file=env.json']);
    });
  });
}
