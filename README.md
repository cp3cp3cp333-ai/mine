# 晴空牧场 · 救救小羊

这是一个面向抖音竖屏场景的固定布局消除闯关原型。当前开放 1～3 关，棋盘引擎支持最多 8 列 × 12 行。

## 本地运行

仓库是无依赖静态页面，使用 Python 自带服务器即可：

```bash
cd /workspace/mine
python3 -m http.server 4173
```

然后打开 `http://127.0.0.1:4173/`。

## 已实现的玩法

- 每关固定棋盘布局，不使用随机数；第 1 关为 5 列 × 6 行，棋盘保留 12 个空位。
- 点击列选择顶部同类棋子，再点击空列或顶部同类的目标列；目标列空间不足时，超出的棋子留在原列。
- 一列填满同一种棋子后自动锁定；全部棋子归组后弹出过关弹窗。
- 小羊露头后自动进入最多 4 个篮子，不能从篮子取出。
- 默认 2 个临时位，可通过看广告增加到最多 8 个；临时位可以和棋盘互相转移单个棋子。
- “整理”按列归拢同类棋子但不改变列号；“撤回”恢复上一步状态；两种道具均带广告确认流程。
- 无可行移动时弹出失败框，可看广告增加临时位后继续。

关卡布局集中在 `game.js` 的 `LEVELS` 中，列数组按“底部到顶部”书写。新增关卡时请保持普通棋子数量为行数的整数倍，并将棋盘容量与空位校验一起更新。

## 发布到网页

仓库内的 `.github/workflows/pages.yml` 会在 `main` 更新后自动打包并发布到 GitHub Pages。第一次发布需要仓库管理员在 GitHub 的 **Settings → Pages** 中将发布来源设为 **GitHub Actions**；发布完成后地址为：

`https://cp3cp3cp333-ai.github.io/mine/`

## Godot 本地工程与 APK

Godot 工程在 [`godot/`](godot/) 目录，使用 Godot 4.3+ 打开 `project.godot` 即可运行。当前第 1 关固定为 5 列 × 6 行，竖屏视口 540 × 960，并实现列顶部同类棋子选择、目标列容量限制、满列锁定、临时位、整理、撤回、卡死提示和重玩。

导出 Android 调试包前，在 Godot 的 **Editor → Editor Settings → Export → Android** 配置 Android SDK、JDK 和导出模板，然后执行：

```bash
godot --path godot --export-debug Android godot/build/sunny-pasture-debug.apk
```

本次已生成并校验的 APK：[`godot/build/sunny-pasture-debug.apk`](godot/build/sunny-pasture-debug.apk)。它是 arm64 调试包，已通过 Android v2/v3 签名校验，可直接安装到支持 arm64 的 Android 手机进行体验。
