# 小食痰记官网素材

2026-11-05。采用用户选定的第三套「奶蛙生活手账」，保留深棕首屏、黄色标题和奶油白内容区，增加角色动作变化。

## 效果图

- [动作版桌面与 H5 效果图](homepage-direction-03-mascot-poses.png) 是本轮页面视觉参考。
- [第三套原始效果图](homepage-direction-03-original.png) 保留最初选定的布局。
- [素材预览](mascot-preview.html) 可用浏览器打开，对照人物在奶油白和深棕底色上的表现。

效果图用于确定排版和人物位置，细小文字和 App 内数字存在生成误差。网页中的 App 展示应使用下方实机原图，页面标题、正文和按钮应使用真正的 HTML 文字。

## 8 张动作素材

| 文件 | 姿势 | 网页位置 |
| --- | --- | --- |
| [milk-frog-hero-reclining.png](milk-frog-hero-reclining.png) | 侧躺托腮 | 桌面首屏主视觉 |
| [milk-frog-meal-bowl.png](milk-frog-meal-bowl.png) | 盘腿捧碗 | AI 记餐介绍 |
| [milk-frog-trends-magnifier.png](milk-frog-trends-magnifier.png) | 蹲着拿放大镜 | 趋势内容与趋势标签 |
| [milk-frog-smoking-pause.png](milk-frog-smoking-pause.png) | 坐着伸手示意等等 | 吸烟记录内容与标签 |
| [milk-frog-health-heart.png](milk-frog-health-heart.png) | 蜷坐抱心 | 健康汇总与支持说明 |
| [milk-frog-peek-curious.png](milk-frog-peek-curious.png) | 歪头扒边探身 | 支持入口的小互动 |
| [milk-frog-mobile-wave.png](milk-frog-mobile-wave.png) | 侧坐挥手 | 手机 H5 首屏 |
| [milk-frog-footer-upsidedown.png](milk-frog-footer-upsidedown.png) | 倒挂挥手 | 桌面页尾点缀 |

以上为透明 PNG，使用内置图片生成与参考图编辑完成。每张都以原角色全身及正脸图为参照，保持黄色梨形身体、浅色肚皮、绿眼圈黑眼珠和平嘴。它们是独立文件，可按板块切换。页尾素材本身已经倒置，使用时保持文件方向。

## 原始素材

| 文件 | 来源 |
| --- | --- |
| [app-screen-diary.png](app-screen-diary.png) | 用户提供的饮食首页实机截图 |
| [app-screen-trends.png](app-screen-trends.png) | 用户提供的趋势实机截图 |
| [app-screen-smoking.png](app-screen-smoking.png) | 用户提供的戒烟实机截图 |
| [app-screen-profile.png](app-screen-profile.png) | 用户提供的个人健康实机截图 |
| [app-icon.png](app-icon.png) | 当前项目 App 图标 |
| [milk-frog-reference-standing.png](milk-frog-reference-standing.png) | 当前项目原始角色全身透明图 |
| [milk-frog-reference-face.png](milk-frog-reference-face.png) | 当前项目原始角色正脸透明图 |

四张 App 截图均按用户原始文件复制，保留原有尺寸和数据。角色站姿与脸部原图用于形象对照。

## 复刻与交付

将 [WEBSITE_RECREATION_PROMPT.md](WEBSITE_RECREATION_PROMPT.md) 中的完整提示词连同本目录提供给网页开发工具。提示词包含页面结构、文案、配色、响应式尺寸、人物映射、交互和实际链接处理。

[assets-manifest.json](assets-manifest.json) 提供文件类型、尺寸、透明通道及使用位置。[generation-prompts.json](generation-prompts.json) 保留本轮人物与效果图生成提示词。

本目录交付网页设计和素材。官网代码开发与部署由后续复刻工作完成。
