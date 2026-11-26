/// Pictures of the owner's own across the top of each group: what part of the picture shows, and the
/// screen to choose it.
library;

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// How many times as wide as high a banner is: as it comes, the flattest and the tallest allowed.
const ambienceBannerAspect = 2.4;
const ambienceFlattestBanner = 4.5;
const ambienceTallestBanner = 1.4;

/// How far a picture can be zoomed in.
const ambienceMaxZoom = 6.0;

/// Which part of a picture the banner shows: how far zoomed in (1 shows as much as fits), and the middle
/// of the part as a share of the picture's width and height.
class BannerFraming {
  const BannerFraming({this.zoom = 1, this.x = 0.5, this.y = 0.5, this.aspect = ambienceBannerAspect});

  /// How many times as wide as high this banner is (smaller is taller).
  final double aspect;

  final double zoom;
  final double x;
  final double y;

  /// The part of a picture of [image] size that shows, in its pixels. It never leaves the picture.
  Rect partOf(Size image) {
    final widest = image.width / image.height > aspect;
    final baseWidth = widest ? image.height * aspect : image.width;
    final width = baseWidth / zoom.clamp(1.0, ambienceMaxZoom);
    final height = width / aspect;
    final left = (x * image.width - width / 2).clamp(0.0, max(0.0, image.width - width));
    final top = (y * image.height - height / 2).clamp(0.0, max(0.0, image.height - height));
    return Rect.fromLTWH(left.toDouble(), top.toDouble(), width, height);
  }

  /// After a drag of [by] screen points over a frame [frameWidth] wide, and zoomed to [zoom].
  BannerFraming moved(Size image, double frameWidth, Offset by, {double? zoom, double? aspect}) {
    final z = (zoom ?? this.zoom).clamp(1.0, ambienceMaxZoom).toDouble();
    final a = (aspect ?? this.aspect).clamp(ambienceTallestBanner, ambienceFlattestBanner).toDouble();
    final part = BannerFraming(zoom: z, x: x, y: y, aspect: a).partOf(image);
    final perPoint = part.width / frameWidth;
    final centre = part.center - by * perPoint;
    // Kept where the picture really is, so dragging back responds at once.
    final kept = BannerFraming(zoom: z, x: centre.dx / image.width, y: centre.dy / image.height, aspect: a).partOf(image).center;
    return BannerFraming(zoom: z, x: kept.dx / image.width, y: kept.dy / image.height, aspect: a);
  }

  Map<String, dynamic> toJson() => {'zoom': zoom, 'x': x, 'y': y, 'aspect': aspect};

  static BannerFraming fromJson(Object? j) {
    if (j is! Map) return const BannerFraming();
    double v(String key, double otherwise) => j[key] is num ? (j[key] as num).toDouble() : otherwise;
    return BannerFraming(
        zoom: v('zoom', 1).clamp(1.0, ambienceMaxZoom),
        x: v('x', 0.5).clamp(0.0, 1.0),
        y: v('y', 0.5).clamp(0.0, 1.0),
        aspect: v('aspect', ambienceBannerAspect).clamp(ambienceTallestBanner, ambienceFlattestBanner));
  }
}

/// What was chosen: the finished banner picture, and how it was framed.
typedef BannerResult = ({Uint8List png, BannerFraming framing});

/// The finished banner as a PNG.
Future<Uint8List> renderBanner(ui.Image image, BannerFraming framing, {int width = 1400}) async {
  final height = (width / framing.aspect).round();
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    framing.partOf(Size(image.width.toDouble(), image.height.toDouble())),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(width, height);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

/// Drag and zoom a picture inside the banner's frame, and set the banner's height. Pops a [BannerResult].
class BannerCropScreen extends StatefulWidget {
  const BannerCropScreen({super.key, required this.bytes, required this.group, this.framing = const BannerFraming()});

  final Uint8List bytes;
  final String group;
  final BannerFraming framing;

  @override
  State<BannerCropScreen> createState() => _BannerCropScreenState();
}

class _BannerCropScreenState extends State<BannerCropScreen> {
  ui.Image? _image;
  bool _broken = false;
  bool _saving = false;
  late BannerFraming _framing = widget.framing;
  double _zoomAtStart = 1;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      // A very large photo is read smaller: the banner needs far fewer pixels.
      final buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
      final description = await ui.ImageDescriptor.encoded(buffer);
      final codec = await description.instantiateCodec(targetWidth: min(description.width, 2800));
      final frame = await codec.getNextFrame();
      codec.dispose();
      description.dispose();
      buffer.dispose();
      if (!mounted) return frame.image.dispose();
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _broken = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final png = await renderBanner(image, _framing);
      if (mounted) Navigator.pop<BannerResult>(context, (png: png, framing: _framing));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("The picture couldn't be saved.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Banner of ${widget.group}', maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          key: const Key('banner-cancel'),
          tooltip: 'Cancel',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            key: const Key('banner-save'),
            tooltip: 'Use this',
            icon: const Icon(Icons.check_rounded),
            onPressed: image == null || _saving ? null : _save,
          ),
        ],
      ),
      body: _broken
          ? const Center(child: Text("That picture can't be opened.", style: TextStyle(color: Colors.white)))
          : image == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, box) {
                    final width = box.maxWidth;
                    final size = Size(image.width.toDouble(), image.height.toDouble());
                    return GestureDetector(
                      // Anywhere on the screen moves the picture; two fingers zoom.
                      key: const Key('banner-drag'),
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (_) => _zoomAtStart = _framing.zoom,
                      onScaleUpdate: (d) => setState(() => _framing = _framing.moved(size, width, d.focalPointDelta,
                          zoom: d.pointerCount > 1 ? _zoomAtStart * d.scale : null)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Drag to move. Pinch to zoom. The sliders set the zoom and the height.',
                                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                          ),
                          Container(
                            width: width,
                            height: width / _framing.aspect,
                            foregroundDecoration: BoxDecoration(border: Border.all(color: Colors.white)),
                            child: CustomPaint(painter: _BannerPainter(image, _framing)),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(Icons.zoom_out_rounded, color: Colors.white),
                                Expanded(
                                  child: Slider(
                                    key: const Key('banner-zoom'),
                                    min: 1,
                                    max: ambienceMaxZoom,
                                    value: _framing.zoom.clamp(1.0, ambienceMaxZoom),
                                    onChanged: (v) => setState(() => _framing = _framing.moved(size, width, Offset.zero, zoom: v)),
                                  ),
                                ),
                                const Icon(Icons.zoom_in_rounded, color: Colors.white),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Icon(Icons.height_rounded, color: Colors.white),
                                Expanded(
                                  // Right is taller: the slider works on height against width.
                                  child: Slider(
                                    key: const Key('banner-height'),
                                    min: 1 / ambienceFlattestBanner,
                                    max: 1 / ambienceTallestBanner,
                                    value: (1 / _framing.aspect).clamp(1 / ambienceFlattestBanner, 1 / ambienceTallestBanner),
                                    semanticFormatterCallback: (v) => 'Banner height ${(v * width).round()}',
                                    onChanged: (v) => setState(() => _framing = _framing.moved(size, width, Offset.zero, aspect: 1 / v)),
                                  ),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Text('${(width / _framing.aspect).round()}',
                                      key: const Key('banner-height-value'),
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class _BannerPainter extends CustomPainter {
  _BannerPainter(this.image, this.framing);

  final ui.Image image;
  final BannerFraming framing;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
        image,
        framing.partOf(Size(image.width.toDouble(), image.height.toDouble())),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );

  @override
  bool shouldRepaint(_BannerPainter old) => old.framing != framing || old.image != image;
}
