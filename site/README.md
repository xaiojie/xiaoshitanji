# 小食痰记官网

原生 HTML / CSS / 少量 JavaScript，无构建步骤、无第三方依赖。素材、效果图与复刻提示词在 [`assets/`](assets)，页面本身用真正的 HTML 文字和布局，App 界面直接嵌入实机截图。

## 文件

| 文件 | 说明 |
| --- | --- |
| `index.html` | 官网单页：首屏、功能特色（01 记餐）、界面一览、数据说明与页尾 |
| `styles.css` | 全部样式，含 1024 / 767 两个断点与 `prefers-reduced-motion` |
| `app.js` | 下载状态、手机菜单、标签与横滑、截图灯箱、入场动画 |
| `terms.html` | 用户协议静态页，文案与 App 内 `AboutDocuments.swift` 一致 |
| `assets/derived/` | 由 `assets/` 原图压出的 webp，页面只引用这里；原图保持不动 |

## 本地预览

```bash
cd site
python3 -m http.server 8099
# 打开 http://127.0.0.1:8099/
```

直接双击 `index.html` 也能看，只是 `file://` 下没有服务器日志可看。

## 配置 App Store 下载地址

`app.js` 顶部：

```js
const DOWNLOAD_URL = "";        // 填 App Store 正式链接
const DOWNLOAD_LABEL = "在 App Store 下载";
```

留空时四个入口（导航、首屏、手机菜单、固定底栏）都是真正的 `disabled` 按钮，文案为「iOS 版即将上线」。填了地址后，脚本会把按钮换成同款样式的 `<a>` 链接，全站一处配置即可生效。

## 交互

- 手机菜单：点开 / 点条目收起 / Esc 关闭并把焦点还给按钮；宽度回到桌面时自动收起。
- 界面一览：桌面三列；768px 及以下切换为「趋势 / 戒烟 / 健康」标签，支持点击、左右方向键、Home/End、触摸横滑，未选中的面板带 `inert`。
- 截图：点击任意截图打开原图灯箱，Esc 或点背景关闭，关闭后焦点与页面滚动位置还原。
- 动效：人物入场淡入 + 8px 位移、悬停轻晃，全部走 `transform` / `opacity`，并遵守 `prefers-reduced-motion`。

## 部署

把 `site/` 整个目录放到任意静态托管即可（Cloudflare Pages / Vercel / nginx）。

- 站内链接都是相对路径，可以放在子目录（如 `/site/`）。
- 隐私政策与支持页仍指向现有线上地址 `https://xiaoshitanji.papaclaoud.top/privacy`、`/support`；用户协议是本站的 `terms.html`。
- 若换域名，只需改这两处外链（`index.html` 的 `#support` 区与页尾、`terms.html` 页尾）。

## 注意

- 页面里的体重、热量、根数等数字来自实机截图，网页自身不写死任何统计数字。
- 人物素材是透明 PNG（`milk-frog-*.png`），`derived/` 里是压缩后的 webp，两者都保留。
- 效果图 `homepage-direction-03-*.png` 只作设计参考，没有用作页面背景。
