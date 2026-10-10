import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recipe.dart';
import '../providers/locale_provider.dart';
import '../services/recipe_translation_service.dart';

/// Shows a recipe name, immediately in its original (or [fallback]) form, and
/// swaps to the on-device translation into the app language once ready.
/// Building this widget (i.e. the card becoming visible) queues the name for
/// lazy batch translation.
class TranslatedRecipeName extends ConsumerStatefulWidget {
  const TranslatedRecipeName(
    this.recipe, {
    super.key,
    this.fallback,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final Recipe recipe;
  final String? fallback;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  ConsumerState<TranslatedRecipeName> createState() =>
      _TranslatedRecipeNameState();
}

class _TranslatedRecipeNameState extends ConsumerState<TranslatedRecipeName> {
  String? _requestedKey;

  void _scheduleRequest(String lang) {
    final key = '${widget.recipe.id}|$lang';
    if (_requestedKey == key) return;
    _requestedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(recipeTranslationProvider.notifier).requestName(widget.recipe);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).code;
    _scheduleRequest(lang);
    final translated = ref.watch(recipeTranslationProvider
        .select((s) => s.byId[widget.recipe.id]?.name));
    return Text(
      translated ?? widget.fallback ?? widget.recipe.name,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
    );
  }
}
