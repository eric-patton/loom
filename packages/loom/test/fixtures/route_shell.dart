import 'package:go_router/go_router.dart';

final router = GoRouter(
  routes: [
    ShellRoute(
      routes: [
        GoRoute(path: '/home'),
        GoRoute(path: '/profile'),
      ],
    ),
    GoRoute(path: '/login'),
  ],
);
