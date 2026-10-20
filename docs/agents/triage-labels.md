# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker. Here the tracker is the agora task board and a label is a task tag (see `issue-tracker.md`).

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

The category roles `bug` and `enhancement` are tags under their own names too.

Tags are set when a task is posted and cannot be changed afterwards, so a role change supersedes the task (`issue-tracker.md`, **Change a ticket's role or category**). A task with no role tag has never been triaged. Every task posted before 2026-10-20 is in that state.

Edit the "Label in our tracker" column to match whatever vocabulary you actually use.
