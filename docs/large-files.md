# 大文件管理（建议使用 Git LFS）

本仓库包含大量离线安装包与驱动等大文件。为避免 `.git` 体积膨胀，建议使用 Git LFS。

## 推荐配置

```bash
git lfs install
git config lfs.storage D:\git-lfs-store\windows-init
```

> `lfs.storage` 可指向任意磁盘路径，用于存放 LFS 实际文件内容。

## 已启用的追踪规则

仓库根目录的 `.gitattributes` 已包含常见大文件类型：

```
*.wim
*.esd
*.iso
*.msi
*.zip
*.exe
sources/$OEM$/$$/Setup/Scripts/Payloads/Defender_Control_2.1.0_Single/**
sources/$OEM$/$$/Setup/Scripts/Payloads/Sunshine/**
sources/$OEM$/$$/Setup/Scripts/DefenderRemover/**
sources/$OEM$/$$/Setup/Scripts/WindowsTerminal/**
```

如需扩展，可直接追加类型或路径。

## 协作注意事项

- 其他协作者需要安装 Git LFS 才能拉取真实文件内容。
- 若暂不需要 payload，可在拉取后按需替换 `sources\$OEM$\$$\Setup\Scripts\Payloads` 目录。
