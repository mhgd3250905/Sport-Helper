# SmartFit 政策站 iOS 补充版本

2026-10-24，从 `https://smartfit-store.pages.dev/` 及其导航实际公开的八个中英文页面取得 HTML，保留原有页面、条款、样式和链接。仅中英文隐私与支持页面增加 iPhone 平台说明：当前无 Key 的本地功能、WKWebView 回环媒体、后台音频、权限、系统备份和删除数据方式。未修改 Android 的原有权限及服务描述。

此目录为**已部署的政策站源码**。2026-10-24 已更新现有 `smartfit-store` Pages 生产项目，部署 ID `7e0472a0-049e-4ad5-a32d-70bd65a35957`，版本地址 `https://7e0472a0.smartfit-store.pages.dev/`；正式地址继续为 `https://smartfit-store.pages.dev/`。没有加入脚本、表单、分析或新依赖。

站点 `icon.png` 使用上层已有的 `assets/icon-512.png`；已核对与线上原文件逐字节相同，SHA-256 为 `225d25822057ddfc28b15ec3d57213fcec7aa63398a0c5610298529cd140b703`，无须在本目录复制一份图标。

核对原生产部署后，另外保留了其 `404.html`、`404/index.html` 和 `_headers`：原站没有自定义重定向或 Pages Functions，安全响应头包含 CSP、Permissions-Policy、X-Frame-Options、Referrer-Policy 与 nosniff，均保持原值。

实际上传目录为本机忽略的 `build/ios-release-private/store-site/staged/`，共十个 HTML、CSS、既有图标及 `_headers`，合计十三个文件，不包含本 README。实际直接上传包为 `build/ios-release-private/store-site/SmartFit-store-ios-2026-10-24-preserved-config.zip`，402,569 bytes，SHA-256 `3e564295dbccc2b3ee2e9c6e316140aad35ea800f63d9f593c38f64fde82298c`。早先十文件包未用于部署。

部署后四个修改路由均返回 200，响应正文 SHA-256 与本地上传稿一致，原安全响应头保留；22:45:26 进一步在浏览器核对四页 iPhone 章节可见、无横向溢出。未操作 `smartfit-media` 素材站。随后已发布 ASC 隐私标签并提交 App Review。网站登录态、Cookies 和凭据不进入本目录。
