---
name: xiaobianqian
description: Use when the user says 小便签、小贴纸、桌面便签、桌面小便签、临时便签、打开小便签、显示小便签、清空小便签、恢复小便签 or 存入语音笔记.
---

# 小便签

## Purpose

Record lightweight, temporary thoughts as colorful desktop capsule notes on macOS. Notes can be edited, searched, categorized, attached to files, deleted, restored from the latest backup, or archived into a user-configured Obsidian note.

The app is a temporary information buffer, not a replacement for a long-term knowledge base:

```text
快速输入 → 桌面胶囊暂存 → 查看与处理 → 删除或存入 Obsidian
```

## Trigger rules

Use this skill when the user asks for:

```text
小便签
小贴纸
桌面便签
桌面小便签
临时便签
打开小便签
显示小便签
清空小便签
恢复小便签
存入语音笔记
```

- If a creation trigger is followed by content, create a note with the remaining content.
- If local file paths are supplied as attachments, pass them after `--` to `scripts/smallnote add`.
- `打开小便签` and `显示小便签` use `scripts/smallnote open`.
- `清空小便签` uses `scripts/smallnote clear`; the latest batch is backed up to `deleted.json`.
- `恢复小便签` uses `scripts/smallnote restore` when a backup exists.
- To archive a known note ID, use `scripts/smallnote archive NOTE_ID`.
- Do not put runtime notes, attachments or credentials into the repository.

## Implemented interaction

- Notes live as independent windows on the left side of the screen and collapse into narrow tabs by default.
- Hovering a tab reveals a same-height first-line preview; clicking it opens an editable card.
- Moving the pointer to the left screen edge wakes all capsules together; leaving the edge collapses unpinned capsules.
- Pinned notes remain in preview width until unpinned.
- Notes can be reordered by vertical dragging; supported trackpads may use a three-finger vertical pan.
- The card supports five semantic colors: urgent/red, inspiration/purple, daily/yellow, work/blue and other/green.
- Search covers title, body, tags and attachment names.
- The control beside search opens batch selection; selected notes can be deleted after confirmation.
- `Ctrl+2` creates a blank note and focuses its body.
- A standalone tap of the right Command key toggles optional cloud Chinese dictation. The first tap starts Volcengine ASR; the second tap finishes it. DeepSeek lightly polishes the result and creates a new note. If polishing fails, raw ASR text is kept.
- Settings control the default expansion mode, default color and editable voice hotwords.

## Commands

```bash
scripts/smallnote add "便签内容" --title "标题" --tags "#标签1 #标签2 #标签3"
scripts/smallnote add "便签内容" -- "/path/to/image.png" "/path/to/file.pdf" "/path/to/note.md"
scripts/smallnote list
scripts/smallnote open
scripts/smallnote stop
scripts/smallnote doctor
scripts/smallnote hotwords
scripts/smallnote clear
scripts/smallnote restore
scripts/smallnote archive "NOTE_ID"
```

The desktop app should be launched through `smallnote open` or `smallnote add`, which builds and opens the local App bundle. Do not run the raw binary in a foreground terminal session.

## Data and configuration

The default data directory is:

```text
~/Library/Application Support/xiaobianqian/
```

Override it with:

```bash
export XIAOBIANQIAN_DATA_DIR="$HOME/Documents/xiaobianqian-data"
```

The directory contains `notes.json`, `deleted.json`, `attachments/` and `voice-hotwords.txt`. Editing a note updates `notes.json` automatically. `archivedAt` is persistent: once a note is archived, later refreshes and changes to other notes keep it marked `已存`.

## Obsidian archive

Configure the vault and target note before using `存笔记`:

```bash
export XIAOBIANQIAN_OBSIDIAN_VAULT="$HOME/ObsidianVault"
export XIAOBIANQIAN_OBSIDIAN_NOTE="临时存放/01语音笔记.md"
```

The target may be absolute or relative to the configured vault. Attachments are copied to `资料库/附件/小便签/NOTE_ID/` and written as clickable Obsidian wikilinks.

Archive metadata currently requests DeepSeek. Supply a key through `XIAOBIANQIAN_DEEPSEEK_API_KEY`, or configure the macOS Keychain service and account with `XIAOBIANQIAN_DEEPSEEK_KEYCHAIN_SERVICE` and `XIAOBIANQIAN_DEEPSEEK_KEYCHAIN_ACCOUNT`. Never write the key into source code, `notes.json` or the App bundle.

## Optional voice configuration

The Swift app reads the optional OpenLess provider configuration from the macOS Keychain item:

```text
service: com.openless.app
account: credentials.v1.chunk.0
```

Voice input may require Input Monitoring and Microphone permissions. Text entry, attachments, search and local note management work without cloud credentials.

## Codex workflow

When creating a note from a Codex request:

1. Remove the trigger phrase and following punctuation from the body.
2. Preserve the user's wording and line breaks.
3. Generate a short content-specific title and exactly three relevant tags.
4. Run `scripts/smallnote add` with `--title` and `--tags`; pass attachments after `--`.
5. Do not archive into Obsidian unless the user explicitly asks.

Keep capture replies brief. This skill is for fast capture and management, not for turning every note into a long-form document.
