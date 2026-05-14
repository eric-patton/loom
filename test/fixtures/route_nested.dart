import 'package:go_router/go_router.dart';

final router = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      routes: [
        GoRoute(path: 'details'),
        GoRoute(path: 'settings'),
      ],
    ),
    GoRoute(path: '/about'),
  ],
);
