# 一键同步脚本说明（cmd）

本仓库提供 `scripts\sync-media.cmd`，用于将 **最小必需内容** 同步到已解压的安装源目录。

## 使用方式

```cmd
scripts\sync-media.cmd D:\WinISO
```

## 同步内容

- `Autounattend.xml` → 目标根目录
- `sources\Autounattend.xml` → 目标 `sources\` 目录
- `sources\$OEM$\$$\Setup\Scripts\` → 目标对应目录（完整复制）

## 说明

- 脚本仅依赖 cmd，可在 WinPE 中使用。
- 如需更细粒度控制，请参考 `docs/minimal-copy.md`。
