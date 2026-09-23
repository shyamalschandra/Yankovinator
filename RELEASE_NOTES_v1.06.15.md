# Yankovinator v1.06.15

## Cogent verse and mid-song resume

- **Cogent lines only.** Each parody line must read as one grammatical sentence or lyric clause, with the original's ending punctuation at the end of the line. Comma-separated rhyme lists are rejected.
- **Retry until it works.** A rejected line is rewritten until it passes. If a candidate request fails, that song resumes from the last saved line instead of aborting the batch.
- **Per-line checkpoints.** Finished lines are stored under `--output-dir/.yankovinator/lines/`. Re-run the same command to continue a stopped song. `--fresh-batch` still wipes the checkpoint.

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
yankovinator --version   # → 1.06.15
```
