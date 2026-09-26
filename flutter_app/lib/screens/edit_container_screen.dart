import 'package:flutter/material.dart';
import '../models/container_model.dart';
import 'container_form_screen.dart';

/// Kept so existing links keep working: editing a box is the three-step [ContainerFormScreen].
class EditContainerScreen extends StatelessWidget {
  const EditContainerScreen({super.key, required this.container});
  final ItemContainer container;

  @override
  Widget build(BuildContext context) => ContainerFormScreen(container: container);
}
