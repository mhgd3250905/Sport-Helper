# SmartFit 政策站 iOS 补充版本

2026-10-24，从 `https://smartfit-store.pages.dev/` 及其导航实际公开的八个中英文页面取得 HTML，保留原有页面、条款、样式和链接。仅中英文隐私与支持页面增加 iPhone 平台说明：当前无 Key 的本地功能、WKWebView 回环媒体、后台音频、权限、系统备份和删除数据方式。未修改 Android 的原有权限及服务描述。

此目录为**本地待部署源码**，不表示线上政策已更新。八个 HTML 与 `style.css` 已完成本地链接检查，中英文隐私页的 iOS 章节已通过浏览器检查。没有加入脚本、表单、分析或新依赖。

站点 `icon.png` 使用上层已有的 `assets/icon-512.png`；已核对与线上原文件逐字节相同，SHA-256 为 `225d25822057ddfc28b15ec3d57213fcec7aa63398a0c5610298529cd140b703`，无须在本目录复制一份图标。

待上传目录为本机忽略的 `build/ios-release-private/store-site/staged/`，由这八个 HTML、CSS 和既有图标组成，共十个文件，不包含本 README。已生成直接上传包 `build/ios-release-private/store-site/SmartFit-store-ios-2026-10-24.zip`，401,026 bytes，SHA-256 `ec58bbca7073d33b518d3daa8d14ed00aa640d845223f0f88046cf2ced1ed2ae`。

部署前需要在指定浏览器登录管理现有 `smartfit-store` Pages 项目的 Cloudflare 账号，核对项目及原部署配置；不得误覆盖 `smartfit-media` 素材站。发布后重新打开四个修改页面核对，再发布 ASC 隐私标签。网站登录态、Cookies 和凭据不进入本目录。
