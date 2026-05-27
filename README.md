# 小便签 xiaobianqian

一个极简 macOS 桌面便签工具：把临时想法、待办、提醒贴到桌面左侧，处理完就删除，值得保留的内容可以归档到 Obsidian。

## 功能

- 彩色桌面便签，自动排列在桌面左侧
- 命令行快速添加、查看、清空、恢复
- 支持图片、PDF、Markdown 等附件
- 单条便签可删除
- 可选：把便签一键归档到 Obsidian 笔记
- 可作为 Codex skill 使用

## 系统要求

- macOS
- 系统自带 Swift 编译器
- Python 3

第一次运行时会自动用 `swiftc` 编译桌面程序。

## 快速开始

```bash
git clone https://github.com/Andrewshilexiaoxi/xiaobianqian.git
cd xiaobianqian
./scripts/smallnote add "晚上记得买水"
./scripts/smallnote open
```

常用命令：

```bash
./scripts/smallnote add "便签内容"
./scripts/smallnote add "带附件的便签" -- "/path/to/file.pdf"
./scripts/smallnote list
./scripts/smallnote clear
./scripts/smallnote restore
./scripts/smallnote open
./scripts/smallnote stop
```

默认数据保存在：

```text
~/Library/Application Support/xiaobianqian
```

你也可以自定义：

```bash
export XIAOBIANQIAN_DATA_DIR="$HOME/Documents/xiaobianqian-data"
```

## Obsidian 归档

如果想使用便签上的 `存笔记` 按钮，需要先设置 Obsidian vault 和目标笔记：

```bash
export XIAOBIANQIAN_OBSIDIAN_VAULT="$HOME/ObsidianVault"
export XIAOBIANQIAN_OBSIDIAN_NOTE="临时存放/01语音笔记.md"
```

也可以手动归档某条便签：

```bash
./scripts/smallnote archive NOTE_ID
```

附件会复制到 vault 里的：

```text
资料库/附件/小便签/NOTE_ID/
```

## 作为 Codex Skill 使用

这个仓库包含一个 `SKILL.md`，可以放到 Codex skills 目录里使用：

```bash
mkdir -p ~/.codex/skills
cp -R . ~/.codex/skills/xiaobianqian
```

之后在 Codex 里说：

```text
小便签 晚上 8 点记得看快递
```

就会创建桌面便签。

## 开源说明

这是一个个人工作流里长出来的小工具，代码很轻量，适合参考、改造和二次开发。它不上传你的便签数据，也不会自动写入 Obsidian，除非你主动配置相关环境变量并使用归档功能。

