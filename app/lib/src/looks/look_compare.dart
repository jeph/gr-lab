import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gr_camera/gr_camera.dart';
import 'package:grphoto/l10n/l10n.dart';
import 'package:grphoto/src/library/image_orientation.dart';
import 'package:grphoto/src/looks/look_preview.dart';
import 'package:grphoto/src/looks/look_widgets.dart';
import 'package:grphoto/src/theme/tokens.dart';
import 'package:grphoto/src/widgets/pressable.dart';
import 'package:intl/intl.dart';

/// A photo looks are previewed on, with what undoes its own rendering.
@immutable
final class PreviewPhoto {
  const new({
    required this.image,
    required this.rerender,
    this.before,
    this.orientation,
  });

  final ImageProvider image;
  final LookRerender rerender;

  /// The look a comparison shows the photo under as its "before", so that
  /// the look the photo was developed with is not part of what it is
  /// compared from; null sets the comparison against the photo as it is.
  final Look? before;

  /// The EXIF orientation (1–8) that shows [image] upright; null shows it
  /// as it is.
  final int? orientation;
}

/// How [LookCompare] sets a photo against the same photo under a look.
enum LookCompareMode {
  /// One over the other, with a divider the user slides across.
  slide,

  /// Both whole, next to each other.
  sideBySide,

  /// One at a time; a tap swaps them.
  single,
}

/// [photo] before and as it would look under [look], whole and upright,
/// as large as the box allows and set against each other as [mode] says
/// \[design\]. Before is the photo as it is, or under its
/// [PreviewPhoto.before]. Without a [look] it is the photo as it is, alone.
///
/// A tap on a picture is the mode's own: it brings the divider of
/// [LookCompareMode.slide] there, and swaps the pictures of
/// [LookCompareMode.single], as their tag does.
class LookCompare extends StatefulWidget {
  const new({
    required this.photo,
    required this.look,
    required this.mode,
    super.key,
  });

  final PreviewPhoto photo;

  /// The look to show the photo under; null when the photo cannot be shown
  /// under one.
  final Look? look;
  final LookCompareMode mode;

  @override
  State<LookCompare> createState() => _LookCompareState();
}

class _LookCompareState extends State<LookCompare> {
  /// The gap between the two pictures of [LookCompareMode.sideBySide].
  static const double _gap = 2;

  /// How far a step of the divider goes for assistive technology.
  static const double _step = .1;

  /// The photo under the look, and the one under its
  /// [PreviewPhoto.before], keep what they worked out when
  /// [LookCompare.mode] moves them to another place.
  final GlobalKey _lookKey = GlobalKey();
  final GlobalKey _beforeKey = GlobalKey();

  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onPhoto,
    onError: (_, _) {},
  );

  /// Width over height of the photo's pixels as stored; null until it has
  /// loaded.
  double? _stored;

  /// How much of the picture's width, from the left, shows the photo as it
  /// is in [LookCompareMode.slide].
  double _split = .5;

  /// Whether [LookCompareMode.single] shows the photo as it is.
  bool _before = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolvePhoto();
  }

  @override
  void didUpdateWidget(LookCompare old) {
    super.didUpdateWidget(old);
    if (widget.photo.image != old.photo.image) _resolvePhoto();
  }

  /// Listens for the photo, to learn its shape; another photo than before
  /// has none until it loads.
  void _resolvePhoto() {
    final stream = widget.photo.image.resolve(
      createLocalImageConfiguration(context),
    );
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stored = null;
    _stream = stream..addListener(_listener);
  }

  void _onPhoto(ImageInfo photo, bool synchronous) {
    final stored = photo.image.width / photo.image.height;
    photo.dispose();
    if (stored == _stored) return;
    // A photo already in the cache answers while this is being built.
    if (synchronous) {
      _stored = stored;
    } else {
      setState(() => _stored = stored);
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  void _slideTo(double split) => setState(() => _split = split.clamp(0.0, 1.0));

  void _swap() => setState(() => _before = !_before);

  /// The photo upright, as it is or under [look].
  Widget _picture({Look? look, Key? key}) => ExifOrientation(
    orientation: widget.photo.orientation ?? 1,
    // The box has the photo's shape, so filling it shows the whole photo.
    child: look == null
        ? Image(image: widget.photo.image, fit: BoxFit.fill)
        : LookPreview(
            key: key ?? _lookKey,
            image: widget.photo.image,
            rerender: widget.photo.rerender,
            look: look,
          ),
  );

  /// What [look] is compared with: the photo under its
  /// [PreviewPhoto.before], or as it is when it has none or cannot be shown
  /// under [look] either, so that both pictures are the photo as taken.
  Widget _beforePicture(Look look) => _picture(
    look: widget.photo.rerender.shows(look) ? widget.photo.before : null,
    key: _beforeKey,
  );

  /// A picture with its [tag] in a bottom corner.
  Widget _tagged(Widget picture, Widget tag, {bool right = false}) => Stack(
    fit: StackFit.expand,
    children: [
      picture,
      Positioned(
        left: right ? null : _tagInset,
        right: right ? _tagInset : null,
        bottom: _tagInset,
        child: tag,
      ),
    ],
  );

  /// How far a tag is from its corner of the picture, and how far beyond
  /// the tag a tap still counts as one on it.
  static const double _tagInset = 8;
  static const double _tagReach = 14;

  @override
  Widget build(BuildContext context) {
    final stored = _stored;
    if (stored == null) return const SizedBox.expand();
    final l10n = context.l10n;
    final shape = orientationSwapsAxes(widget.photo.orientation ?? 1)
        ? 1 / stored
        : stored;
    final look = widget.look;
    if (look == null) {
      return Center(
        key: const Key('look-compare-as-taken'),
        child: AspectRatio(aspectRatio: shape, child: _picture()),
      );
    }
    final beforeTag = l10n.upperCase(l10n.looksBefore);
    final lookTag = l10n.upperCase(l10n.looksPreview);
    switch (widget.mode) {
      case LookCompareMode.slide:
        final percent = NumberFormat.percentPattern(
          Localizations.localeOf(context).toString(),
        );
        return Center(
          child: AspectRatio(
            aspectRatio: shape,
            child: LayoutBuilder(
              builder: (context, box) => Semantics(
                container: true,
                slider: true,
                label: l10n.looksCompareDivider,
                value: percent.format(_split),
                increasedValue: percent.format(
                  (_split + _step).clamp(0.0, 1.0),
                ),
                decreasedValue: percent.format(
                  (_split - _step).clamp(0.0, 1.0),
                ),
                onIncrease: () => _slideTo(_split + _step),
                onDecrease: () => _slideTo(_split - _step),
                child: GestureDetector(
                  key: const Key('look-compare-slide'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _slideTo(d.localPosition.dx / box.maxWidth),
                  onHorizontalDragStart: (d) =>
                      _slideTo(d.localPosition.dx / box.maxWidth),
                  onHorizontalDragUpdate: (d) =>
                      _slideTo(d.localPosition.dx / box.maxWidth),
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      _tagged(
                        _picture(look: look),
                        PhotoTag(lookTag),
                        right: true,
                      ),
                      ClipRect(
                        clipper: _LeftPart(_split),
                        child: _tagged(
                          _beforePicture(look),
                          PhotoTag(beforeTag),
                        ),
                      ),
                      Positioned(
                        left: _split * box.maxWidth - _Divider.width / 2,
                        top: 0,
                        bottom: 0,
                        width: _Divider.width,
                        child: const _Divider(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      case LookCompareMode.sideBySide:
        return LayoutBuilder(
          builder: (context, box) {
            // Next to each other or one above the other, whichever shows
            // the pictures larger.
            final across = _fitted(
              shape,
              Size((box.maxWidth - _gap) / 2, box.maxHeight),
            );
            final down = _fitted(
              shape,
              Size(box.maxWidth, (box.maxHeight - _gap) / 2),
            );
            final horizontal = across.width >= down.width;
            final size = horizontal ? across : down;
            return Center(
              child: Flex(
                direction: horizontal ? Axis.horizontal : Axis.vertical,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.fromSize(
                    key: const Key('look-compare-before'),
                    size: size,
                    child: _tagged(_beforePicture(look), PhotoTag(beforeTag)),
                  ),
                  const SizedBox.square(dimension: _gap),
                  SizedBox.fromSize(
                    key: const Key('look-compare-look'),
                    size: size,
                    child: _tagged(_picture(look: look), PhotoTag(lookTag)),
                  ),
                ],
              ),
            );
          },
        );
      case LookCompareMode.single:
        final pictures = Stack(
          fit: StackFit.expand,
          children: [
            _picture(look: look),
            if (_before) _beforePicture(look),
          ],
        );
        return Center(
          child: AspectRatio(
            aspectRatio: shape,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  button: true,
                  hint: l10n.looksCompareSwapHint,
                  child: GestureDetector(
                    key: const Key('look-compare-single'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _swap,
                    child: pictures,
                  ),
                ),
                // The tag swaps them too, from a little around it: it is
                // small.
                Positioned(
                  left: _tagInset - _tagReach,
                  bottom: _tagInset - _tagReach,
                  child: Semantics(
                    button: true,
                    hint: l10n.looksCompareSwapHint,
                    child: GestureDetector(
                      key: const Key('look-compare-swap'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _swap,
                      child: Padding(
                        padding: const EdgeInsets.all(_tagReach),
                        child: PhotoTag(
                          _before ? beforeTag : lookTag,
                          icon: Icons.swap_horiz_rounded,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  /// The largest size of [shape] (width over height) that fits in [pane].
  static Size _fitted(double shape, Size pane) {
    final width = math.max(0, math.min(pane.width, pane.height * shape));
    return Size(width.toDouble(), width / shape);
  }
}

/// Keeps the part of a box left of [split] of its width.
class _LeftPart extends CustomClipper<Rect> {
  const new(this.split);

  final double split;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(_LeftPart old) => old.split != split;
}

/// The line between the two pictures of [LookCompareMode.slide], with the
/// handle that says it slides.
class _Divider extends StatelessWidget {
  const new();

  static const double width = 32;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Container(
        width: 2,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 3)],
        ),
      ),
      Container(
        width: width,
        height: width,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 6)],
        ),
        child: const RotatedBox(
          quarterTurns: 1,
          child: Icon(
            Icons.unfold_more_rounded,
            size: 20,
            color: Color(0xFF0B0B0C),
          ),
        ),
      ),
    ],
  );
}

/// The ground of a control that lies over a picture (mock `look-photos`
/// A): the app's surface, with the picture showing through it blurred, so
/// that the control reads as lying on the picture \[design\].
class OverPicture extends StatelessWidget {
  const new({required this.child, super.key, this.padding = EdgeInsets.zero});

  static const double radius = 12;

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: c.s2.withValues(alpha: .82),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: c.line2),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The choice of [LookCompareMode], one sign each (mock `.segc`), on the
/// ground of a control over a picture ([OverPicture]).
class LookCompareModeSwitch extends StatelessWidget {
  const new({required this.selected, required this.onSelect, super.key});

  final LookCompareMode selected;
  final ValueChanged<LookCompareMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final l10n = context.l10n;
    return OverPicture(
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in LookCompareMode.values)
            Tooltip(
              message: switch (mode) {
                LookCompareMode.slide => l10n.looksCompareSlide,
                LookCompareMode.sideBySide => l10n.looksCompareSideBySide,
                LookCompareMode.single => l10n.looksCompareSingle,
              },
              child: Semantics(
                button: true,
                selected: mode == selected,
                child: Pressable(
                  key: ValueKey('look-compare:${mode.name}'),
                  onTap: () => onSelect(mode),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 36,
                    height: 30,
                    decoration: BoxDecoration(
                      color: mode == selected ? c.s4 : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: IconTheme(
                      data: IconThemeData(
                        size: 18,
                        color: mode == selected ? c.t1 : c.t2,
                      ),
                      child: switch (mode) {
                        LookCompareMode.slide => const Icon(
                          Icons.compare_rounded,
                        ),
                        // Two panes next to each other.
                        LookCompareMode.sideBySide => const RotatedBox(
                          quarterTurns: 1,
                          child: Icon(Icons.splitscreen_rounded),
                        ),
                        LookCompareMode.single => const Icon(
                          Icons.crop_din_rounded,
                        ),
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The photos a look can be previewed on, as small pictures to pick from
/// (mock `look-photos` A). They share the length of [axis] between them,
/// each up to a largest size, so that every photo is in view and none of
/// them scrolls \[design\]. With [ownFirst] the first is the look's own
/// photo: it carries a mark, and a line sets it apart from the others.
class PreviewPhotoSwitch extends StatelessWidget {
  const new({
    required this.photos,
    required this.labels,
    required this.selected,
    required this.onSelect,
    super.key,
    this.axis = Axis.horizontal,
    this.ownFirst = false,
  });

  final List<PreviewPhoto> photos;

  /// What each photo is, for assistive technology and its tooltip.
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Across, as a row, or down, as a column.
  final Axis axis;
  final bool ownFirst;

  /// The most a small picture takes in a row and in a column; it gives up
  /// length along [axis] when the photos have less than that each.
  static const Size _largestAcross = Size(58, 40);
  static const Size _largestDown = Size(52, 52);

  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final c = GrColors.of(context);
    final down = axis == Axis.vertical;
    final ownApart = ownFirst && photos.length > 1;
    return Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < photos.length; i++) ...[
          if (i > (ownApart ? 1 : 0)) const SizedBox.square(dimension: _gap),
          Flexible(
            child: SizedBox.fromSize(
              size: down ? _largestDown : _largestAcross,
              child: _small(c, i),
            ),
          ),
          if (i == 0 && ownApart)
            Container(
              key: const Key('look-photo-own-line'),
              width: down ? 22 : 1,
              height: down ? 1 : 22,
              margin: down
                  ? const EdgeInsets.symmetric(vertical: 4)
                  : const EdgeInsets.symmetric(horizontal: 4),
              color: c.line2,
            ),
        ],
      ],
    );
  }

  /// The small picture of photo [i], which picks it; ringed when it is the
  /// one picked.
  Widget _small(GrColors c, int i) => Tooltip(
    message: labels[i],
    child: Semantics(
      button: true,
      selected: i == selected,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Pressable(
            key: ValueKey('look-photo:$i'),
            onTap: () => onSelect(i),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  width: 2,
                  color: i == selected ? c.accent : Colors.transparent,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: ExifOrientation(
                  orientation: photos[i].orientation ?? 1,
                  child: Image(
                    image: _decodedSmall(photos[i].image),
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
          if (i == 0 && ownFirst)
            Positioned(
              right: -4,
              bottom: -4,
              child: IgnorePointer(
                child: Container(
                  key: const Key('look-photo-own'),
                  width: 19,
                  height: 19,
                  decoration: BoxDecoration(
                    color: c.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line2),
                  ),
                  child: Icon(Icons.bookmark_rounded, size: 11, color: c.t1),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  /// [photo] decoded no larger than a small picture needs, however large
  /// the preview asks for it: there may be several of them.
  static ImageProvider _decodedSmall(ImageProvider photo) => ResizeImage(
    switch (photo) {
      ResizeImage(:final imageProvider) => imageProvider,
      _ => photo,
    },
    width: _longSide,
    height: _longSide,
    policy: ResizeImagePolicy.fit,
  );

  /// Pixels on the long side of a small picture: enough for the short
  /// side of a 3:2 photo to fill it at four device pixels to one.
  static const int _longSide = 240;
}
