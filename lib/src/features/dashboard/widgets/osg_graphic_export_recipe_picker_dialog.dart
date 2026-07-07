import "package:flutter/material.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/osg/osg_bake_models.dart";

/// Shows a dialog listing [recipes], each with an **Export** action.
/// Returns null if the operator dismisses without choosing.
Future<OsgBakeRecipe?> showOsgGraphicExportRecipePickerDialog(
  BuildContext context, {
  required List<OsgBakeRecipe> recipes,
}) {
  return showDialog<OsgBakeRecipe>(
    context: context,
    builder: (BuildContext ctx) {
      final double gap12 = scaleDimension(ctx, 12);
      final double gap8 = scaleDimension(ctx, 8);
      return AlertDialog(
        title: const Text("Export OSG Graphics"),
        content: SizedBox(
          width: scaleDimension(ctx, 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: recipes
                  .map(
                    (OsgBakeRecipe recipe) => Padding(
                      padding: EdgeInsets.only(bottom: gap12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  recipe.name,
                                  style: Theme.of(ctx).textTheme.titleSmall,
                                ),
                                Text(
                                  recipe.cues
                                      .map(osgBakeCueSummaryLabel)
                                      .join("; "),
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: gap8),
                          FilledButton.tonal(
                            onPressed: () =>
                                Navigator.of(ctx).pop(recipe),
                            child: const Text("Export"),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
        ],
      );
    },
  );
}
