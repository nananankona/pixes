import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' hide FilledButton; // for MaterialPageRoute
import 'package:pixes/appdata.dart';
import 'package:pixes/components/message.dart';
import 'package:pixes/pages/main_page.dart';
import 'package:pixes/utils/translation.dart';

class LockPage extends StatefulWidget {
  const LockPage({super.key});

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _verify() {
    final input = _controller.text;
    final password = appdata.settings["lockPassword"];
    final pin = appdata.settings["lockPin"];

    if ((password != null && password.isNotEmpty && input == password) ||
        (pin != null && pin.isNotEmpty && input == pin)) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainPage()),
      );
    } else {
      showToast(context, message: "Incorrect password/PIN".tl);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      content: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FluentIcons.lock, size: 64),
            const SizedBox(height: 24),
            Text("Locked".tl, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              width: 300,
              child: TextBox(
                controller: _controller,
                placeholder: "Enter Password or PIN".tl,
                obscureText: true,
                onSubmitted: (_) => _verify(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              child: Text("Unlock".tl),
              onPressed: _verify,
            ),
          ],
        ),
      ),
    );
  }
}


