import 'package:shared_preferences/shared_preferences.dart';

/// Service untuk mengelola status tutorial dan hints untuk first-time users
class TutorialService {
  TutorialService._private();
  static final TutorialService instance = TutorialService._private();

  // Keys untuk tracking tutorial completion
  static const String _keyHomeScreenTutorial = 'tutorial_home_screen_completed';
  static const String _keyTransactionTutorial = 'tutorial_transaction_completed';
  static const String _keyCategoriesTutorial = 'tutorial_categories_completed';
  static const String _keyAccountsTutorial = 'tutorial_accounts_completed';
  static const String _keyGoalsTutorial = 'tutorial_goals_completed';
  static const String _keyGroupTutorial = 'tutorial_group_completed';
  static const String _keyFirstLaunch = 'app_first_launch';

  /// Check if this is the first time the app is launched
  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFirstLaunch) ?? true;
  }

  /// Mark first launch as completed
  Future<void> markFirstLaunchCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFirstLaunch, false);
  }

  /// Check if home screen tutorial has been completed
  Future<bool> hasCompletedHomeScreenTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHomeScreenTutorial) ?? false;
  }

  /// Mark home screen tutorial as completed
  Future<void> markHomeScreenTutorialCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHomeScreenTutorial, true);
  }

  /// Check if transaction tutorial has been completed
  Future<bool> hasCompletedTransactionTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyTransactionTutorial) ?? false;
  }

  /// Mark transaction tutorial as completed
  Future<void> markTransactionTutorialCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTransactionTutorial, true);
  }

  /// Check if categories tutorial has been completed
  Future<bool> hasCompletedCategoriesTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCategoriesTutorial) ?? false;
  }

  /// Mark categories tutorial as completed
  Future<void> markCategoriesTutorialCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCategoriesTutorial, true);
  }

  /// Check if accounts tutorial has been completed
  Future<bool> hasCompletedAccountsTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAccountsTutorial) ?? false;
  }

  /// Mark accounts tutorial as completed
  Future<void> markAccountsTutorialCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAccountsTutorial, true);
  }

  /// Check if goals tutorial has been completed
  Future<bool> hasCompletedGoalsTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyGoalsTutorial) ?? false;
  }

  /// Mark goals tutorial as completed
  Future<void> markGoalsTutorialCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGoalsTutorial, true);
  }

  /// Check if group tutorial has been completed
  Future<bool> hasCompletedGroupTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyGroupTutorial) ?? false;
  }

  /// Mark group tutorial as completed
  Future<void> markGroupTutorialCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGroupTutorial, true);
  }

  /// Reset all tutorials (for testing or user request)
  Future<void> resetAllTutorials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHomeScreenTutorial, false);
    await prefs.setBool(_keyTransactionTutorial, false);
    await prefs.setBool(_keyCategoriesTutorial, false);
    await prefs.setBool(_keyAccountsTutorial, false);
    await prefs.setBool(_keyGoalsTutorial, false);
    await prefs.setBool(_keyGroupTutorial, false);
  }
}
