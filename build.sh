#!/bin/bash
# 编译 ClipboardManager 并手动拼装成 .app bundle(无需 Xcode),最后 ad-hoc 签名。
set -euo pipefail

# 切到脚本所在目录(路径可能含空格)
cd "$(dirname "$0")"

APP_NAME="ClipboardManager"
APP="${APP_NAME}.app"
CONFIG="release"

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)"
EXEC="${BIN_PATH}/${APP_NAME}"

if [[ ! -f "${EXEC}" ]]; then
	echo "错误:未找到可执行文件 ${EXEC}" >&2
	exit 1
fi

# 生成 App 图标(若还没有 AppIcon.icns)
if [[ ! -f "AppIcon.icns" ]]; then
	if command -v iconutil >/dev/null 2>&1; then
		echo "==> 生成 App 图标"
		"${EXEC}" --makeicon "${APP_NAME}.iconset" \
			&& iconutil -c icns "${APP_NAME}.iconset" -o "AppIcon.icns" \
			&& rm -rf "${APP_NAME}.iconset" \
			|| echo "    图标生成失败,跳过(不影响功能)"
	else
		echo "    未找到 iconutil,跳过图标生成"
	fi
fi

echo "==> 拼装 ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
cp "${EXEC}" "${APP}/Contents/MacOS/${APP_NAME}"
cp "Info.plist" "${APP}/Contents/Info.plist"

if [[ -f "AppIcon.icns" ]]; then
	cp "AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

echo "==> ad-hoc 代码签名"
codesign --force --deep --sign - "${APP}"
codesign -dv "${APP}" 2>&1 | sed 's/^/    /' || true

echo ""
echo "✅ 构建完成:${PWD}/${APP}"
echo "   运行:  open \"${APP}\""
echo "   首次启动若被 Gatekeeper 拦截:右键 App → 打开,或到「系统设置 → 隐私与安全性」放行。"
