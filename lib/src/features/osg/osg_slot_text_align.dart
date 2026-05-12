import "package:flutter/material.dart";

import "package:obs_clipshow/src/osg/osg_models.dart";

/// Combined horizontal + vertical alignment for slot text inside [FittedBox].
Alignment osgSlotAlignment(
  OsgSlotTextAlign horizontal,
  OsgSlotVerticalAlign vertical,
) {
  final double x = switch (horizontal) {
    OsgSlotTextAlign.left => -1,
    OsgSlotTextAlign.center => 0,
    OsgSlotTextAlign.right => 1,
  };
  final double y = switch (vertical) {
    OsgSlotVerticalAlign.top => -1,
    OsgSlotVerticalAlign.center => 0,
    OsgSlotVerticalAlign.bottom => 1,
  };
  return Alignment(x, y);
}

TextAlign osgSlotTextAlignToFlutterTextAlign(OsgSlotTextAlign a) {
  switch (a) {
    case OsgSlotTextAlign.left:
      return TextAlign.left;
    case OsgSlotTextAlign.center:
      return TextAlign.center;
    case OsgSlotTextAlign.right:
      return TextAlign.right;
  }
}
