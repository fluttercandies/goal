/// Public API for programmatic use of the goal ledger.
library;

// Generic string utilities (`trunc`, `cell`, `statusColumnWidth`) stay
// internal: they are listLine's implementation details, not ledger API.
export 'src/cli/format.dart'
    show
        age,
        stamp,
        fullStamp,
        listLine,
        footerCounts,
        statusViewOrder,
        statusViewRank;
export 'src/cli/goal_cli.dart' show runGoalCli, statusWords;
export 'src/models/goal_entry.dart';
export 'src/models/goal_meta.dart';
export 'src/models/goal_note.dart';
export 'src/models/goal_priority.dart';
export 'src/models/goal_status.dart';
export 'src/store/events.dart';
export 'src/store/goal_store.dart';
