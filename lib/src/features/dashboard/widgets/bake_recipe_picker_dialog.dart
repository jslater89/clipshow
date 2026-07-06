import "package:flutter/material.dart";

import "package:obs_clipshow/src/app/ui_scale.dart";
import "package:obs_clipshow/src/osg/osg_bake_models.dart";

/// Whether the operator wants a recipe queued for later or baked right away.
enum BakeRecipePickerAction { queue, now }

/// Result of [showBakeRecipePickerDialog]: the chosen recipe plus how to run it.
class BakeRecipePickerChoice {
  const BakeRecipePickerChoice({required this.recipe, required this.action});

  final OsgBakeRecipe recipe;
  final BakeRecipePickerAction action;
}

/// Shows a dialog listing [recipes], each with a "Queue" and a "Now" action.
/// Returns null if the operator dismisses without choosing.
Future<BakeRecipePickerChoice?> showBakeRecipePickerDialog(
  BuildContext context, {
  required List<OsgBakeRecipe> recipes,
  required bool bakeNowEnabled,
}) {
  return showDialog<BakeRecipePickerChoice>(
    context: context,
    builder: (BuildContext ctx) {
      final double gap12 = scaleDimension(ctx, 12);
      final double gap8 = scaleDimension(ctx, 8);
      return AlertDialog(
        title: const Text("Bake With Recipe"),
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
                          OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(
                              BakeRecipePickerChoice(
                                recipe: recipe,
                                action: BakeRecipePickerAction.queue,
                              ),
                            ),
                            child: const Text("Queue"),
                          ),
                          SizedBox(width: gap8),
                          FilledButton.tonal(
                            onPressed: bakeNowEnabled
                                ? () => Navigator.of(ctx).pop(
                                    BakeRecipePickerChoice(
                                      recipe: recipe,
                                      action: BakeRecipePickerAction.now,
                                    ),
                                  )
                                : null,
                            child: const Text("Now"),
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
