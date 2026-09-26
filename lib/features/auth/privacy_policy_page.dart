import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show rootBundle;

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Política de Privacidade'),
      ),
      child: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString('POLITICA_DE_PRIVACIDADE.md'),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CupertinoActivityIndicator());
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Text(
                snapshot.data!,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            );
          },
        ),
      ),
    );
  }
}
