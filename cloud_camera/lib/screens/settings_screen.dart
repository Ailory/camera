import 'package:flutter/material.dart';

import '../app_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onBack,
  });

  final AppController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final profile = controller.accountProfile;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 20, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Назад к камере',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Настройки',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 27,
                                  foregroundImage: profile?.pictureUrl != null
                                      ? NetworkImage(profile!.pictureUrl!)
                                      : null,
                                  child: Text(profile?.initials ?? 'G'),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        controller.isSignedIn
                                            ? (profile?.name
                                                          .trim()
                                                          .isNotEmpty ==
                                                      true
                                                  ? profile!.name
                                                  : 'Google подключён')
                                            : 'Google Drive',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        controller.isSignedIn
                                            ? (profile?.email ??
                                                  'Автоматическое сохранение включено')
                                            : 'Войдите с главного экрана',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  controller.isSignedIn
                                      ? Icons.cloud_done_rounded
                                      : Icons.cloud_off_rounded,
                                  color: controller.isSignedIn
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.tertiary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Конфиденциальность',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 16),
                                const _PrivacyLine(
                                  icon: Icons.lock_outline_rounded,
                                  text: 'Пароль вводится только на официальной странице Google.',
                                ),
                                const SizedBox(height: 14),
                                const _PrivacyLine(
                                  icon: Icons.folder_outlined,
                                  text: 'Приложение работает только с файлами, созданными Cloud Camera.',
                                ),
                                const SizedBox(height: 14),
                                const _PrivacyLine(
                                  icon: Icons.phone_android_rounded,
                                  text: 'При отсутствии интернета снимок временно хранится на устройстве и отправляется автоматически.',
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!controller.isConfigured) ...[
                          const SizedBox(height: 16),
                          Card(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  const Icon(Icons.build_circle_outlined),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'В этой сборке не настроен Google OAuth. Обратитесь к разработчику приложения.',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
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

class _PrivacyLine extends StatelessWidget {
  const _PrivacyLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
