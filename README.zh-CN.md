<p align="center"><img src="doc/logo.png" width="160" alt="goal logo"></p>

# goal

在命令行里追踪目标与任务。为 AI agent 打造，也适合与 agent 协作的你。

[English](README.md) | 简体中文

<p align="center">
<a href="https://pub.dev/packages/goal"><img src="https://img.shields.io/pub/v/goal.svg" alt="pub version"></a>
<a href="https://pub.dev/packages/goal/score"><img src="https://img.shields.io/pub/points/goal.svg" alt="pub points"></a>
<a href="https://github.com/fluttercandies/goal/actions"><img src="https://img.shields.io/github/actions/workflow/status/fluttercandies/goal/ci.yml?branch=main" alt="ci"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
</p>

## 安装

```bash
dart pub global activate goal
```

要求 Dart 3.4 及以上。

## 快速上手

```bash
$ goal init
ok ledger at .goal

$ goal add "修复 iOS 登录崩溃" -p1 --round R12
ok #1 created (todo) round=R12 修复 iOS 登录崩溃

$ goal set 1 wip --agent agent_a
ok 1 todo -> wip +agent=agent_a

$ goal set 1 done "改了 login.dart; flutter test 通过"
ok 1 wip -> done +note="改了 login.dart; flutter test 通过"

$ goal add "增加离线模式" -p2
ok #2 created (todo) 增加离线模式

$ goal ready
2  P2  todo  5m  -  增加离线模式
-- 1 ready
```

## 命令

| 命令 | 作用 |
| --- | --- |
| `goal init` | 在 `./.goal` 建账（每个项目一次） |
| `goal add <标题>` | 新增票据；旗标：`-p0..-p3` `--deps a,b` `--round R` `-m <正文>` |
| `goal set <id> [状态] [备注...]` | 更新票据——改状态、加备注、设 `--agent`、`--deps`、`--round`、`-pN`，或用 `--title`/`--detail` 纠正标题与正文（`-` 从 stdin 读入，同 `-m`）。不带参数 = 心跳。id 带 `#` 前缀也认。 |
| `goal list [过滤词]` | 列出票据。裸词过滤：状态、轮次、优先级、`#id` 或标题文字，可自由组合（`goal list wip R12`）。同样支持旗标形式：`-pN` `--round <R>` `--id <id>` |
| `goal ready` | 依赖全部完成的 todo，按优先级排序 |
| `goal show <id>` | 查看单张票据的全部信息——归档票据也能查，带 `[archived]` 标记 |
| `goal render [-o file] [--json]` | 导出可读的 markdown 视图，或 JSON（JSON 备份含归档段） |
| `goal archive [--dry-run]` | 把已完成票据移出活跃台账；`--dry-run` 预览将移动哪些 |
| `goal rm <id>` | 彻底删除一张票据（记入审计日志；id 永不复用） |

状态：`todo` `wip` `done` `blocked` `failed` `parked`。

备注带时间戳、只增不改——收账细节就写在这里：改了哪些文件、跑了什么
验证、证据链接。

```bash
$ goal set 3 done "files: a.dart, b.dart; verify: dart test; evidence: docs/3.png"
```

长备注可以从管道读入，绕开引号问题：`goal set 3 done -m -` 从 stdin 读取。

多行和特殊字符随处可用：标题、正文、备注全部原样存储——`show` 就是原样
视图——而回执、`list` 与 `render` 始终输出结构安全的单行内容。
`goal add` 后面的裸词会自动拼成一个标题，忘加引号也能一次成功；回执会写明
每个字段的新值（`+agent=… +deps=1,2 +note="…"`），无需再跑一次 `show` 核对。

## 依赖

带 `--deps` 的票据会等所有依赖变为 `done`（或已归档）后才出现在
`goal ready` 里。循环依赖会被直接拒绝。

```bash
$ goal add "复审修复面" --deps 3
$ goal ready          # 3 号票完成前这里为空
```

## 数据在哪里？

所有数据都在项目旁的 `./.goal/` 目录。请把 `.goal/` 加入
`.gitignore`；想放到别处，设置 `GOAL_HOME` 即可。

完成的票据由 `goal archive` 移入归档，活跃台账始终保持精简。
`goal render` 随时能导出 markdown 或 JSON 快照。

## 许可

MIT
