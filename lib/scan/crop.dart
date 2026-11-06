import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

/// Ritaglio della foto dello scontrino, tutto in puro Dart (nessun ML Kit,
/// OpenCV o servizio esterno). I calcoli pesanti girano in un isolate.
///
/// Gli angoli sono normalizzati (0..1) rispetto all'immagine già ruotata, in
/// ordine: alto-sinistra, alto-destra, basso-destra, basso-sinistra.

/// Angoli dell'immagine intera.
const fullQuad = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];

/// Anteprima per la schermata di ritaglio.
class CropPreview {
  /// JPEG ridotto (lato lungo al massimo [previewSide]) già orientato e ruotato.
  final Uint8List jpeg;
  final int width;
  final int height;

  /// Angoli proposti dal rilevamento automatico (o l'immagine intera).
  final List<Offset> detected;

  const CropPreview(this.jpeg, this.width, this.height, this.detected);
}

const previewSide = 1200;
const outputSide = 2000;

img.Image? _decode(Uint8List bytes, int quarterTurns) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  final t = quarterTurns % 4;
  if (t != 0) im = img.copyRotate(im, angle: 90 * t);
  return im;
}

img.Image _fit(img.Image im, int side) {
  final long = math.max(im.width, im.height);
  if (long <= side) return im;
  return im.width >= im.height
      ? img.copyResize(im, width: side, interpolation: img.Interpolation.average)
      : img.copyResize(im, height: side, interpolation: img.Interpolation.average);
}

/// Anteprima e angoli proposti. Null se il formato non è leggibile (es. HEIC):
/// in quel caso la foto va all'AI così com'è.
Future<CropPreview?> makePreview(Uint8List bytes, {int quarterTurns = 0}) => Isolate.run(() {
      final im = _decode(bytes, quarterTurns);
      if (im == null) return null;
      final small = _fit(im, previewSide);
      return CropPreview(
        Uint8List.fromList(img.encodeJpg(small, quality: 80)),
        small.width,
        small.height,
        detectReceipt(small),
      );
    });

/// Ritaglia, raddrizza e ricodifica in JPEG (lato lungo al massimo
/// [outputSide]). Null se l'immagine non è leggibile.
Future<Uint8List?> cropToJpeg(Uint8List bytes, List<Offset> quad, {int quarterTurns = 0}) => Isolate.run(() {
      final im = _decode(bytes, quarterTurns);
      if (im == null) return null;
      final out = isFullQuad(quad) ? _fit(im, outputSide) : warpQuad(im, quad, maxSide: outputSide);
      return Uint8List.fromList(img.encodeJpg(out, quality: 85));
    });

bool isFullQuad(List<Offset> q) {
  for (var i = 0; i < 4; i++) {
    if ((q[i] - fullQuad[i]).distance > 0.002) return false;
  }
  return true;
}

// ------------------------------------------------------------ rilevamento

/// Soglia di Otsu su un istogramma a 256 livelli.
int otsuThreshold(List<int> hist) {
  final total = hist.fold<int>(0, (a, b) => a + b);
  if (total == 0) return 128;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, threshold = 128;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t;
    }
  }
  return threshold;
}

/// Angoli dello scontrino: la carta chiara è la regione chiara connessa più
/// grande; gli angoli sono i suoi punti estremi lungo le diagonali. Se la
/// regione è troppo piccola, troppo grande o la forma è strana, restituisce
/// l'immagine intera ([fullQuad]).
List<Offset> detectReceipt(img.Image src) {
  final s = _fit(src, 400);
  final w = s.width, h = s.height, n = w * h;
  final lum = Uint8List(n);
  final hist = List<int>.filled(256, 0);
  for (final p in s) {
    final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
    lum[p.y * w + p.x] = l;
    hist[l]++;
  }
  final t = otsuThreshold(hist);
  // Componente chiara più grande (4-connessa).
  final label = Int32List(n);
  var bestSize = 0, bestLabel = 0, next = 0;
  final stack = Int32List(n);
  for (var i = 0; i < n; i++) {
    if (lum[i] <= t || label[i] != 0) continue;
    next++;
    var size = 0, top = 0;
    stack[top++] = i;
    label[i] = next;
    while (top > 0) {
      final k = stack[--top];
      size++;
      final x = k % w, y = k ~/ w;
      void visit(int j) {
        if (lum[j] > t && label[j] == 0) {
          label[j] = next;
          stack[top++] = j;
        }
      }

      if (x > 0) visit(k - 1);
      if (x < w - 1) visit(k + 1);
      if (y > 0) visit(k - w);
      if (y < h - 1) visit(k + w);
    }
    if (size > bestSize) {
      bestSize = size;
      bestLabel = next;
    }
  }
  final ratio = bestSize / n;
  if (bestLabel == 0 || ratio < 0.15 || ratio > 0.95) return fullQuad;

  var tl = 0, tr = 0, br = 0, bl = 0;
  var minSum = 1 << 30, maxSum = -1, maxDiff = -(1 << 30), minDiff = 1 << 30;
  for (var i = 0; i < n; i++) {
    if (label[i] != bestLabel) continue;
    final x = i % w, y = i ~/ w;
    final sum = x + y, diff = x - y;
    if (sum < minSum) {
      minSum = sum;
      tl = i;
    }
    if (sum > maxSum) {
      maxSum = sum;
      br = i;
    }
    if (diff > maxDiff) {
      maxDiff = diff;
      tr = i;
    }
    if (diff < minDiff) {
      minDiff = diff;
      bl = i;
    }
  }
  Offset pt(int i) => Offset(((i % w) + 0.5) / w, ((i ~/ w) + 0.5) / h);
  final quad = [pt(tl), pt(tr), pt(br), pt(bl)];
  // Il quadrilatero deve coprire buona parte della regione e non essere degenere.
  final area = quadArea(quad) * n;
  if (area < bestSize * 0.6 || area < n * 0.1 || !isConvex(quad)) return fullQuad;
  return quad;
}

/// Area (formula di Gauss) di un quadrilatero.
double quadArea(List<Offset> q) {
  var a = 0.0;
  for (var i = 0; i < 4; i++) {
    final p = q[i], r = q[(i + 1) % 4];
    a += p.dx * r.dy - r.dx * p.dy;
  }
  return a.abs() / 2;
}

bool isConvex(List<Offset> q) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4], c = q[(i + 2) % 4];
    final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
    if (cross.abs() < 1e-9) return false;
    final s = cross > 0 ? 1 : -1;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}

// ------------------------------------------------------------ prospettiva

/// Omografia che porta i 4 punti [from] nei 4 punti [to]: 9 coefficienti
/// (l'ultimo vale 1). Null se i punti sono degeneri.
List<double>? homography(List<Offset> from, List<Offset> to) {
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = from[i].dx, y = from[i].dy, u = to[i].dx, v = to[i].dy;
    a[2 * i]
      ..[0] = x
      ..[1] = y
      ..[2] = 1
      ..[6] = -u * x
      ..[7] = -u * y
      ..[8] = u;
    a[2 * i + 1]
      ..[3] = x
      ..[4] = y
      ..[5] = 1
      ..[6] = -v * x
      ..[7] = -v * y
      ..[8] = v;
  }
  // Eliminazione di Gauss con pivot parziale.
  for (var col = 0; col < 8; col++) {
    var piv = col;
    for (var r = col + 1; r < 8; r++) {
      if (a[r][col].abs() > a[piv][col].abs()) piv = r;
    }
    if (a[piv][col].abs() < 1e-12) return null;
    final tmp = a[col];
    a[col] = a[piv];
    a[piv] = tmp;
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final f = a[r][col] / a[col][col];
      for (var k = col; k < 9; k++) {
        a[r][k] -= f * a[col][k];
      }
    }
  }
  return [for (var i = 0; i < 8; i++) a[i][8] / a[i][i], 1];
}

Offset applyHomography(List<double> m, Offset p) {
  final d = m[6] * p.dx + m[7] * p.dy + m[8];
  return Offset((m[0] * p.dx + m[1] * p.dy + m[2]) / d, (m[3] * p.dx + m[4] * p.dy + m[5]) / d);
}

/// Raddrizza il quadrilatero [quad] (normalizzato) di [src] in un rettangolo.
img.Image warpQuad(img.Image src, List<Offset> quad, {int maxSide = outputSide}) {
  final sw = src.width, sh = src.height;
  final q = [for (final p in quad) Offset(p.dx * sw, p.dy * sh)];
  var outW = math.max((q[1] - q[0]).distance, (q[2] - q[3]).distance);
  var outH = math.max((q[3] - q[0]).distance, (q[2] - q[1]).distance);
  final scale = math.min(1.0, maxSide / math.max(outW, outH));
  final ow = math.max(1, (outW * scale).round()), oh = math.max(1, (outH * scale).round());
  final rect = [Offset.zero, Offset(ow.toDouble(), 0), Offset(ow.toDouble(), oh.toDouble()), Offset(0, oh.toDouble())];
  final m = homography(rect, q);
  if (m == null) return _fit(src, maxSide);

  final rgb = src.convert(numChannels: 3, format: img.Format.uint8).getBytes(order: img.ChannelOrder.rgb);
  final out = Uint8List(ow * oh * 3);
  var o = 0;
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      final yy = y + 0.5, xx = x + 0.5;
      final d = m[6] * xx + m[7] * yy + m[8];
      final u = (m[0] * xx + m[1] * yy + m[2]) / d - 0.5;
      final v = (m[3] * xx + m[4] * yy + m[5]) / d - 0.5;
      // Bilineare, con i bordi bloccati.
      final x0 = u.floor().clamp(0, sw - 1), y0 = v.floor().clamp(0, sh - 1);
      final x1 = math.min(x0 + 1, sw - 1), y1 = math.min(y0 + 1, sh - 1);
      final fx = (u - x0).clamp(0.0, 1.0), fy = (v - y0).clamp(0.0, 1.0);
      final i00 = (y0 * sw + x0) * 3, i10 = (y0 * sw + x1) * 3, i01 = (y1 * sw + x0) * 3, i11 = (y1 * sw + x1) * 3;
      for (var c = 0; c < 3; c++) {
        final top = rgb[i00 + c] + (rgb[i10 + c] - rgb[i00 + c]) * fx;
        final bottom = rgb[i01 + c] + (rgb[i11 + c] - rgb[i01 + c]) * fx;
        out[o++] = (top + (bottom - top) * fy).round();
      }
    }
  }
  return img.Image.fromBytes(width: ow, height: oh, bytes: out.buffer, numChannels: 3);
}
