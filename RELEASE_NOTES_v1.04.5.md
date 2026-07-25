# Yankovinator v1.04.5

## What's new

- **`--midi-progress`:** optional lightweight MIDI cues while batch workers run (macOS, interactive terminal only)
- **Per worker:** distinct GM instrument on job start, throttled pulses synced to indeterminate bars, completion note per job
- **Batch:** 10% overall milestones + finish chord; lazy Apple DLS synth, no audio when stderr is not a TTY

## Example

```bash
yankovinator --input-dir ./songs --themes-dir ./themes --output-dir ./out \
  --workers 10 --candidates 10 --midi-progress --verbose
```

## Install

```bash
brew update && brew upgrade shyamalschandra/yankovinator/yankovinator
```

Universal: [v1.04.5 release](https://github.com/shyamalschandra/Yankovinator/releases/download/v1.04.5/yankovinator-universal.tar.gz)
