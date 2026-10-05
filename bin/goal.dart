import 'dart:io';

import 'package:goal/src/cli/goal_cli.dart';

Future<void> main(List<String> args) async {
  final code = await runGoalCli(args);
  // exit() drops in-flight writes; flush first so piped output is complete.
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
