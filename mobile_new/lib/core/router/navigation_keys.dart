import 'package:flutter/material.dart';

/// Clé globale du navigator racine.
/// Utilisée par FCMService pour naviguer depuis l'extérieur du widget tree.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
