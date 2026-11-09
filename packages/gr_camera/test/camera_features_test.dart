import 'package:flutter_test/flutter_test.dart';
import 'package:gr_camera/gr_camera.dart';

bool _slots(GrModel? model, String? firmware) => CameraBody(
  model: model,
  firmware: firmware,
).supports(CameraFeature.lookSlots);

void main() {
  test('a feature with a minimum firmware starts at that version', () {
    expect(_slots(GrModel.gr4, '1.03'), isFalse);
    expect(_slots(GrModel.gr4, '1.04'), isTrue);
    expect(_slots(GrModel.gr4, '1.20'), isTrue);
    expect(_slots(GrModel.gr4, '1.20\u0000 '), isTrue, reason: 'NUL padding');
    expect(_slots(GrModel.gr4, null), isFalse, reason: 'firmware not read');
    expect(_slots(GrModel.gr4, 'beta'), isFalse, reason: 'not a version');
  });

  test('a feature from any version needs no firmware reading', () {
    expect(_slots(GrModel.gr4Hdf, null), isTrue);
    expect(_slots(GrModel.gr4Hdf, '1.00'), isTrue);
  });

  test('a model the feature does not list never has it', () {
    expect(_slots(GrModel.gr3, '9.99'), isFalse);
    expect(
      const CameraBody(
        model: GrModel.gr3,
        firmware: '2.20',
      ).minimumFirmware(CameraFeature.lookSlots),
      isNull,
    );
    expect(_slots(null, '1.20'), isFalse, reason: 'unknown model');
  });
}
