import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scontrini/scan/crop.dart';

/// Fondo scuro con un quadrilatero chiaro (lo "scontrino") e qualche riga
/// scura dentro (il testo).
img.Image _receipt(List<Offset> corners, {int w = 600, int h = 800}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(60, 52, 48));
  img.fillPolygon(im,
      vertices: [for (final p in corners) img.Point(p.dx * w, p.dy * h)], color: img.ColorRgb8(245, 242, 235));
  for (var i = 0; i < 8; i++) {
    final y = (h * (0.3 + i * 0.05)).round();
    img.drawLine(im, x1: (w * 0.4).round(), y1: y, x2: (w * 0.6).round(), y2: y, color: img.ColorRgb8(30, 30, 30));
  }
  return im;
}

void main() {
  test('rileva gli angoli di uno scontrino storto', () {
    const corners = [Offset(0.25, 0.1), Offset(0.78, 0.15), Offset(0.72, 0.92), Offset(0.2, 0.88)];
    final found = detectReceipt(_receipt(corners));
    for (var i = 0; i < 4; i++) {
      expect((found[i] - corners[i]).distance, lessThan(0.03), reason: 'angolo $i: ${found[i]}');
    }
  });

  test('immagine uniforme o regione troppo piccola: immagine intera', () {
    final plain = img.Image(width: 300, height: 400);
    img.fill(plain, color: img.ColorRgb8(200, 200, 200));
    expect(detectReceipt(plain), fullQuad);
    final tiny = _receipt(const [Offset(0.45, 0.45), Offset(0.55, 0.45), Offset(0.55, 0.55), Offset(0.45, 0.55)]);
    expect(detectReceipt(tiny), fullQuad);
  });

  test('omografia: i punti finiscono dove devono', () {
    const from = [Offset(0, 0), Offset(100, 0), Offset(100, 200), Offset(0, 200)];
    const to = [Offset(10, 20), Offset(90, 5), Offset(120, 210), Offset(-5, 190)];
    final m = homography(from, to)!;
    for (var i = 0; i < 4; i++) {
      expect((applyHomography(m, from[i]) - to[i]).distance, lessThan(1e-6));
    }
    expect(homography(from, const [Offset(0, 0), Offset(0, 0), Offset(0, 0), Offset(0, 0)]), isNull);
  });

  test('raddrizzamento: lo scontrino riempie il rettangolo', () {
    const corners = [Offset(0.25, 0.1), Offset(0.78, 0.15), Offset(0.72, 0.92), Offset(0.2, 0.88)];
    final out = warpQuad(_receipt(corners), corners, maxSide: 500);
    expect(out.height, 500);
    expect(out.width, inInclusiveRange(250, 380));
    // Angoli e bordi chiari: dentro lo scontrino, non sul fondo.
    for (final (x, y) in [(3, 3), (out.width - 4, 3), (3, out.height - 4), (out.width - 4, out.height - 4)]) {
      expect(out.getPixel(x, y).r, greaterThan(200), reason: '($x, $y)');
    }
  });

  test('ritaglio completo da JPEG, con rotazione', () async {
    final src = Uint8List.fromList(img.encodeJpg(_receipt(fullQuad, w: 300, h: 200)));
    final preview = (await makePreview(src, quarterTurns: 1))!;
    expect((preview.width, preview.height), (200, 300));
    final jpeg = (await cropToJpeg(src, fullQuad, quarterTurns: 1))!;
    final back = img.decodeJpg(jpeg)!;
    expect((back.width, back.height), (200, 300));
    expect(await makePreview(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('Otsu separa due popolazioni', () {
    final hist = List<int>.filled(256, 0);
    hist[40] = 500;
    hist[220] = 300;
    final t = otsuThreshold(hist);
    expect(t, inInclusiveRange(40, 219));
  });
}
