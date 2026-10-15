// ============================================================
// 容器侧移动端改造样板（Capacitor Android）
// 用法：
//   1) 复制到 android/app/src/main/java/<你的包路径>/MainActivity.java
//   2) 把第一行 package 改成你的包名；下方 Toast 文案可改
//   3) npx cap sync android → 重新构建
//
// 为什么放在原生侧（而不是 JS 插件）：
//   若用"远程 URL"模式（server.url 指向线上站点），页面里的 JS 不属于本 App，
//   @capacitor/app 的 JS 监听器无法注入 → 状态栏与返回键必须在原生层处理。
//   即使不是远程模式，原生侧处理也更稳：不依赖页面 JS、不受前端改版影响。
//
// 解决三个现象：
//   1. 内容顶到状态栏      → 消费 systemBars + 刘海 insets
//   2. 右滑/返回键直接退出  → 优先回退 WebView 历史；根页面则"再按一次退出"
//   3. 键盘顶起/遮挡输入框  → IME insets 与导航栏取较大值作为底部留白
// ============================================================
package com.example.app;   // ← 改成你的包名

import android.os.Bundle;
import android.view.View;
import android.webkit.WebView;
import android.widget.Toast;

import androidx.activity.OnBackPressedCallback;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

    /** 双击退出：两次返回的时间间隔阈值（毫秒） */
    private static final long EXIT_INTERVAL_MS = 2000L;

    private long lastBackPress = 0L;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        applyWindowInsets();
        installBackHandler();
    }

    private void applyWindowInsets() {
        final View content = findViewById(android.R.id.content);
        if (content == null) {
            return;
        }
        ViewCompat.setOnApplyWindowInsetsListener(content, (v, windowInsets) -> {
            Insets bars = windowInsets.getInsets(
                    WindowInsetsCompat.Type.systemBars()
                            | WindowInsetsCompat.Type.displayCutout());
            Insets ime = windowInsets.getInsets(WindowInsetsCompat.Type.ime());
            int bottom = Math.max(bars.bottom, ime.bottom);
            v.setPadding(bars.left, bars.top, bars.right, bottom);
            return WindowInsetsCompat.CONSUMED;
        });
    }

    private void installBackHandler() {
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                WebView webView = (getBridge() != null) ? getBridge().getWebView() : null;
                if (webView != null && webView.canGoBack()) {
                    webView.goBack();
                    return;
                }
                long now = System.currentTimeMillis();
                if (now - lastBackPress < EXIT_INTERVAL_MS) {
                    finish();
                    return;
                }
                lastBackPress = now;
                Toast.makeText(MainActivity.this, "再按一次退出应用", Toast.LENGTH_SHORT).show();
            }
        });
    }
}
