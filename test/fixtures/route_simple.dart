import 'package:go_router/go_router.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/'),
    GoRoute(path: '/settings'),
  ],
);
