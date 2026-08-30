import 'package:dan_player/window_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal minimum primitive constants match the shared size', () {
    expect(WindowGeometryPolicy.normalMinimumWidth, 507);
    expect(WindowGeometryPolicy.normalMinimumHeight, 320);
    expect(
      WindowGeometryPolicy.normalMinimumSize,
      const WindowGeometrySize(
        WindowGeometryPolicy.normalMinimumWidth,
        WindowGeometryPolicy.normalMinimumHeight,
      ),
    );
  });

  group('WindowGeometryPolicy.restore', () {
    test('missing and malformed sizes fall back to the default', () {
      for (final value in <Object?>[
        null,
        '',
        '507',
        '507,320,1',
        'width,height',
        'NaN,507',
        'Infinity,507',
        '-1,507',
        '0,507',
        507,
      ]) {
        final result = WindowGeometryPolicy.restore(<String, Object?>{
          WindowGeometryPolicy.schemaKey:
              WindowGeometryPolicy.currentSchemaVersion,
          WindowGeometryPolicy.sizeKey: value,
        });

        expect(result.size, WindowGeometryPolicy.defaultSize,
            reason: 'unexpected size for $value');
      }
    });

    test('valid dimensions are parsed and independently constrained', () {
      final result = WindowGeometryPolicy.restore(<String, Object>{
        WindowGeometryPolicy.schemaKey:
            WindowGeometryPolicy.currentSchemaVersion,
        WindowGeometryPolicy.sizeKey: '400,300',
        WindowGeometryPolicy.maximizedKey: false,
      });

      expect(
        result.size,
        WindowGeometryPolicy.normalMinimumSize,
      );
      expect(result.migratedLegacyMinimumSquare, isFalse);
      expect(result.needsRewrite, isTrue);
    });

    test('whitespace and finite decimal sizes are accepted', () {
      final result = WindowGeometryPolicy.restore(<String, Object>{
        WindowGeometryPolicy.schemaKey:
            WindowGeometryPolicy.currentSchemaVersion,
        WindowGeometryPolicy.sizeKey: ' 1280.25 , 756.75 ',
      });

      expect(result.size, const WindowGeometrySize(1280.25, 756.75));
      expect(result.isMaximized, isFalse);
    });

    test('legacy maximized minimum square migrates to default', () {
      for (final size in ['507,507', '506.4,506.4', '508,508']) {
        final result = WindowGeometryPolicy.restore(<String, Object>{
          WindowGeometryPolicy.sizeKey: size,
          WindowGeometryPolicy.maximizedKey: true,
        });

        expect(result.size, WindowGeometryPolicy.defaultSize,
            reason: 'expected migration for $size');
        expect(result.migratedLegacyMinimumSquare, isTrue);
        expect(result.needsRewrite, isTrue);
      }
    });

    test('legacy numeric maximize flag participates in migration', () {
      final result = WindowGeometryPolicy.restore(<String, Object>{
        WindowGeometryPolicy.schemaKey: 0,
        WindowGeometryPolicy.sizeKey: '506.4,507.0',
        WindowGeometryPolicy.maximizedKey: 1,
      });

      expect(result.size, WindowGeometryPolicy.defaultSize);
      expect(result.isMaximized, isTrue);
      expect(result.migratedLegacyMinimumSquare, isTrue);
    });

    test('legacy pollution migration requires every condition', () {
      final fixtures = <Map<String, Object>>[
        <String, Object>{
          WindowGeometryPolicy.sizeKey: '506.4,506.4',
          WindowGeometryPolicy.maximizedKey: false,
        },
        <String, Object>{
          WindowGeometryPolicy.sizeKey: '506.4,600',
          WindowGeometryPolicy.maximizedKey: true,
        },
        <String, Object>{
          WindowGeometryPolicy.schemaKey:
              WindowGeometryPolicy.currentSchemaVersion,
          WindowGeometryPolicy.sizeKey: '506.4,506.4',
          WindowGeometryPolicy.maximizedKey: true,
        },
        <String, Object>{
          WindowGeometryPolicy.schemaKey:
              WindowGeometryPolicy.currentSchemaVersion + 1,
          WindowGeometryPolicy.sizeKey: '506.4,506.4',
          WindowGeometryPolicy.maximizedKey: true,
        },
        <String, Object>{
          WindowGeometryPolicy.schemaKey: 'invalid',
          WindowGeometryPolicy.sizeKey: '506.4,506.4',
          WindowGeometryPolicy.maximizedKey: true,
        },
      ];

      for (final fixture in fixtures) {
        final result = WindowGeometryPolicy.restore(fixture);
        expect(result.migratedLegacyMinimumSquare, isFalse,
            reason: 'unexpected migration for $fixture');
      }
    });

    test('current schema preserves an intentional 507 square', () {
      final result = WindowGeometryPolicy.restore(<String, Object>{
        WindowGeometryPolicy.schemaKey:
            WindowGeometryPolicy.currentSchemaVersion,
        WindowGeometryPolicy.sizeKey: '507.0,507.0',
        WindowGeometryPolicy.maximizedKey: true,
      });

      expect(result.size, const WindowGeometrySize(507, 507));
      expect(result.migratedLegacyMinimumSquare, isFalse);
      expect(result.needsRewrite, isFalse);
    });
  });

  group('WindowGeometryPolicy persistence', () {
    test('encode validates and writes canonical fields', () {
      expect(
        WindowGeometryPolicy.encode(
          size: const WindowGeometrySize(400, 200),
          isMaximized: true,
        ),
        <String, Object>{
          WindowGeometryPolicy.schemaKey:
              WindowGeometryPolicy.currentSchemaVersion,
          WindowGeometryPolicy.sizeKey: '507.0,320.0',
          WindowGeometryPolicy.maximizedKey: true,
        },
      );
    });

    test('encode rejects non-finite programmatic sizes via default', () {
      expect(
        WindowGeometryPolicy.encodeSize(
          const WindowGeometrySize(double.nan, 700),
        ),
        '1280.0,756.0',
      );
      expect(
        WindowGeometryPolicy.encodeSize(
          const WindowGeometrySize(double.infinity, 700),
        ),
        '1280.0,756.0',
      );
    });

    test('canonical current values do not request a rewrite', () {
      final encoded = WindowGeometryPolicy.encode(
        size: const WindowGeometrySize(900, 700),
        isMaximized: false,
      );

      final restored = WindowGeometryPolicy.restore(encoded);
      expect(restored.size, const WindowGeometrySize(900, 700));
      expect(restored.needsRewrite, isFalse);
    });
  });
}
