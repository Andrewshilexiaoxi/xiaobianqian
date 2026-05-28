---
name: xiaobianqian
description: Use when the user says 小便签, 小贴纸, 桌面便签, 桌面小便签, 贴到桌面, 记录到桌面, 临时便签, 小边签, 小编签, 打开小便签, 显示小便签, 清空小便签, or 存入语音笔记 to record, manage, or archive colorful desktop sticky notes on Andrew's Mac. Supports image, PDF, and Markdown attachments.
---

# 小便签

## Purpose

Record lightweight, temporary thoughts as colorful desktop sticky notes on Andrew's Mac.
Notes may include file attachments. Supported attachment types include images, PDFs, and Markdown files; other files can be copied as generic attachments if explicitly provided.
Each desktop sticky note has a `存笔记` button. When Obsidian environment variables are configured, that button appends the note to a chosen Obsidian note.

## Trigger Rules

Use this skill whenever the user's message includes any of these trigger phrases:

```text
小便签
小贴纸
桌面便签
桌面小便签
贴到桌面
记录到桌面
临时便签
小边签
小编签
打开小便签
显示小便签
清空小便签
存入语音笔记
```

- If the user writes any creation trigger followed by content, create a new desktop sticky note with all content after the trigger phrase.
- Creation triggers are: `小便签`, `小贴纸`, `桌面便签`, `桌面小便签`, `贴到桌面`, `记录到桌面`, `临时便签`, `小边签`, `小编签`.
- If the user writes a creation trigger on its own and then provides text on following lines, record the following text.
- If the user includes local file paths as attachments, pass them after `--` so they are copied into the sticky-note attachment folder.
- If the user asks to `清空小便签`, clear all current sticky notes permanently.
- If the user asks to `恢复小便签`, restore the most recently deleted or cleared sticky-note batch only if an older backup exists. Current delete and clear operations are permanent.
- If the user asks to `打开小便签`, start or refresh the desktop sticky-note display.
- If the user asks to `显示小便签`, start or refresh the desktop sticky-note display.
- If the user asks to store a sticky note into the voice note, use `smallnote archive NOTE_ID` when the note ID is known.
- After a sticky note is archived successfully, the archived state must persist in `notes.json` via the note's `archivedAt` field. The desktop UI must keep showing `已存` for that note after any later add/delete/refresh operation, not only immediately after the button click.
- If the user asks what this skill does, explain the above briefly.

## Commands

Use the bundled helper script:

```bash
scripts/smallnote add "便签内容"
scripts/smallnote add "便签内容" -- "/path/to/image.png" "/path/to/file.pdf" "/path/to/note.md"
scripts/smallnote list
scripts/smallnote clear
scripts/smallnote restore
scripts/smallnote archive "NOTE_ID"
scripts/smallnote open
```

## Obsidian Voice Note Archive

To enable Obsidian archive, configure both environment variables:

```text
XIAOBIANQIAN_OBSIDIAN_VAULT=/path/to/your/ObsidianVault
XIAOBIANQIAN_OBSIDIAN_NOTE=临时存放/01语音笔记.md
```

Archive format:

```markdown

#### 自动标题
> 核心内容
YYYY-MM-DD HH:MM
#标签1 #标签2 #标签3
```

The archive command auto-generates a short title, preserves the note's core content without omissions, adds attachment names when present, and writes exactly three tags.

When a sticky note has attachments, `smallnote archive NOTE_ID` copies those attachments into the Obsidian vault under:

```text
资料库/附件/小便签/NOTE_ID/
```

The voice-note entry must include clickable Obsidian wikilinks to those copied files, for example:

```markdown
> 附件：[[资料库/附件/小便签/NOTE_ID/file.pdf|file.pdf]]
```

## Workflow

1. Extract the note body.
   - Remove the leading trigger phrase and common punctuation after it, such as `：`, `:`, `，`, `,`, or whitespace.
   - Preserve line breaks and the user's wording.
2. Identify attachments only when the user provides explicit local file paths or attached files available in the local workspace.
3. If the extracted body is non-empty, run `scripts/smallnote add`, passing attachment paths after `--` when present.
4. Reply briefly that the note has been added, mentioning the attachment count if any.
5. If the extracted body is empty and the user clearly wants to create a note, ask for the content.

## Important

- Do not save these notes into Obsidian unless the user explicitly asks.
- Keep the response short; this is a capture workflow, not a writing workflow.
- The notes are intentionally temporary and can be cleared daily. Single-note delete and clear-all are permanent after confirmation.
