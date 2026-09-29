import 'package:flutter/widgets.dart';

/// Adds the bottom system inset (gesture bar / navigation bar) to [base] so
/// scrollable content is not hidden under edge-to-edge system bars.
EdgeInsets withBottomInset(BuildContext context, EdgeInsets base) =>
    base.copyWith(bottom: base.bottom + MediaQuery.paddingOf(context).bottom);
