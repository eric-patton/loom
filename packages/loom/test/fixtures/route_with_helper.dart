import 'package:go_router/go_router.dart';

class AppRouter {
  GoRouter buildRouter() {
    return GoRouter(
      routes: [
        _homeRoute(),
        GoRoute(path: '/login'),
      ],
    );
  }

  GoRoute _homeRoute() {
    return GoRoute(path: '/home');
  }
}
