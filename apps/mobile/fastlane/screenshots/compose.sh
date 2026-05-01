#!/bin/bash
# Compose store screenshots: dark background + keyword/title text + screenshot
# Output: 1320x2868 (App Store 6.9" requirement)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CANVAS_W=1320
CANVAS_H=2868
BG_COLOR="#141416"
# Strip timestamps from PNG to avoid spurious git diffs
PNG_STRIP="-define png:exclude-chunks=date,time"

# Font settings
# Try font name first (works with system ImageMagick), fall back to file path (Homebrew)
resolve_font() {
  local name="$1" path="$2"
  if magick -list font 2>/dev/null | grep "Font: ${name}$" >/dev/null 2>&1; then
    echo "$name"
  else
    echo "$path"
  fi
}

resolve_font_candidates() {
  local fallback=""
  while [ "$#" -gt 0 ]; do
    local name="$1" path="$2"
    [ -z "$fallback" ] && fallback="$path"
    if magick -list font 2>/dev/null | grep "Font: ${name}$" >/dev/null 2>&1; then
      echo "$name"
      return
    fi
    if [ -f "$path" ]; then
      echo "$path"
      return
    fi
    shift 2
  done
  echo "$fallback"
}
FONT_EN_BOLD="$(resolve_font Helvetica-Bold /System/Library/Fonts/Helvetica.ttc)"
FONT_EN_REG="$(resolve_font Helvetica /System/Library/Fonts/Helvetica.ttc)"
FONT_JA_BOLD="$(resolve_font Hiragino-Sans-W7 '/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc')"
FONT_JA_REG="$(resolve_font Hiragino-Sans-W3 '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc')"
FONT_ZH_BOLD="$(resolve_font PingFang-SC-Semibold /System/Library/Fonts/PingFang.ttc)"
FONT_ZH_REG="$(resolve_font PingFang-SC-Regular /System/Library/Fonts/PingFang.ttc)"
FONT_KO_BOLD="$(resolve_font_candidates \
  Noto-Sans-CJK-KR-Bold /Library/Fonts/NotoSansCJKkr-Bold.otf \
  Pretendard-Bold /Library/Fonts/Pretendard-Bold.otf \
  AppleSDGothicNeo-Bold /System/Library/Fonts/AppleSDGothicNeo.ttc)"
FONT_KO_REG="$(resolve_font_candidates \
  Noto-Sans-CJK-KR-Regular /Library/Fonts/NotoSansCJKkr-Regular.otf \
  Pretendard-Regular /Library/Fonts/Pretendard-Regular.otf \
  AppleSDGothicNeo-Regular /System/Library/Fonts/AppleSDGothicNeo.ttc)"
HERO_ILLUSTRATION="${SCRIPT_DIR}/assets/remote-agent-train-laptop.png"

# Screenshot definitions: key, keyword_en, title_en, keyword_ja, title_ja, keyword_zh, title_zh, keyword_ko, title_ko
SCREENSHOTS=(
  "01_session_list|Self-hosted Codex|Run Codex on Mac/Linux. Control from your phone.|セルフホストCodex|Mac/LinuxのCodexをスマホから操作|自托管 Codex|在 Mac/Linux 运行 Codex，用手机控制|셀프 호스팅 Codex|Mac/Linux의 Codex를 휴대폰으로 제어"
  "02_recent_sessions|Continue Codex|Codex sessions sync; Claude Code is also supported.|Codexをどこでも継続|Codexセッションを端末間で引き継ぎ。Claude Codeにも対応|随处继续 Codex|Codex 会话随设备同步，也支持 Claude Code|Codex 이어가기|Codex 세션을 기기 간 이어가기. Claude Code도 지원"
  "03_approval_list|Approve Codex|Handle multiple Codex approvals at a glance.|Codex承認をまとめて|複数のCodexセッションを一目で承認|审批 Codex|一览处理多个 Codex 审批|Codex 승인|여러 Codex 승인을 한눈에 처리"
  "04_multi_question|Codex decisions|Answer questions without opening a laptop.|Codexの判断をタッチで|PCを開かずに質問へ回答|Codex 决策|不用打开电脑也能回答问题|Codex 판단|노트북 없이 질문에 답하기"
  "05_explorer|Codex Explorer|Explorer shows the files behind the work.|Codexのファイル閲覧|Explorerで作業中のファイルを確認|Codex Explorer|Explorer 展示背后的文件|Codex Explorer|Explorer로 작업 파일 확인"
  "06_git_actions|Ship Codex changes|Stage, commit, push, or revert from the app.|Codexの変更を出荷|stage、commit、push、revertまで|交付 Codex 变更|在应用中 stage、commit、push 或 revert|Codex 변경 반영|앱에서 stage, commit, push, revert"
  "07_images_screenshots|Visual context|MCP images and Mac screenshots stay in context.|Codexに視覚情報を|MCP画像やMacスクショを文脈に|视觉上下文|在上下文中查看 MCP 图片和 Mac 截图|시각 맥락|MCP 이미지와 Mac 스크린샷을 함께"
  "08_network_resilience|Mobile-ready Codex|Pending prompts resend after reconnect.|不安定な通信でもCodex|pendingプロンプトを再接続後に再送|移动 Codex|重连后自动重发 pending 提示|모바일 Codex|재연결 후 pending 프롬프트 자동 재전송"
)

IPAD_SCREENSHOTS=(
  "01_workspace_overview|Codex workspace on iPad|Chat, sessions, and Git side by side|iPadでCodexワークスペース|会話、セッション、Gitを並べて確認|iPad 上的 Codex 工作区|聊天、会话和 Git 并排显示|iPad의 Codex 워크스페이스|채팅, 세션, Git을 나란히"
  "02_workspace_explorer|Explorer beside Codex|Keep project files next to the conversation|Codexの横にExplorer|チャットしながらファイル確認|Codex 旁的 Explorer|对话旁边查看项目文件|Codex 옆 Explorer|대화 옆에서 파일 확인"
  "03_approval_context|Approve Codex in context|Answer without leaving the workspace|文脈のままCodex承認|ワークスペースを離れず判断|在上下文中审批 Codex|不离开工作区即可回答|맥락 안에서 Codex 승인|워크스페이스를 떠나지 않고 답변"
  "04_approval_queue|Codex approval queue|Review waiting sessions together|Codex承認キュー|複数セッションの待ちをまとめて処理|Codex 审批队列|集中处理等待中的会话|Codex 승인 대기열|기다리는 세션을 한곳에서 처리"
  "05_dark_workspace|Focused Codex workspace|A desktop-like layout on iPad and Mac|集中できるCodex画面|iPad/macOSでデスクトップのように|专注 Codex 工作区|iPad 和 Mac 上的桌面式布局|집중을 위한 Codex 화면|iPad와 Mac의 데스크톱 같은 레이아웃"
)

compose_hero_screenshot() {
  local key="$1" keyword="$2" title="$3" lang_dir="$4" font_bold="$5" font_reg="$6"
  local input="${SCRIPT_DIR}/${lang_dir}/${key}.png"
  local output="${SCRIPT_DIR}/${lang_dir}/${key}_framed.png"

  local text_fill="#111111"
  local subtitle_fill="rgba(17,17,17,0.75)"
  local bg_gradient="gradient:#FFFFFF-#F4F4F5"

  local src_w src_h
  read -r src_w src_h <<< "$(magick identify -format '%w %h' "$input")"

  local ss_y=1010
  local max_w=1020
  local scale_ratio
  scale_ratio=$(echo "scale=6; $max_w / $src_w" | bc)
  local scaled_w=$max_w
  local scaled_h
  scaled_h=$(echo "$src_h * $scale_ratio / 1" | bc)

  local ss_x=$(( (CANVAS_W - scaled_w) / 2 ))
  local corner_radius=125

  echo "Composing hero: $key ($lang_dir)"

  magick -size "${scaled_w}x${scaled_h}" xc:none \
    -fill white -draw "roundrectangle 0,0 $((scaled_w-1)),$((scaled_h-1)) ${corner_radius},${corner_radius}" \
    /tmp/mask_$$.png

  magick "$input" -resize "${scaled_w}x${scaled_h}" \
    /tmp/mask_$$.png -alpha off -compose CopyOpacity -composite \
    /tmp/ss_$$.png

  magick -size "${scaled_w}x${scaled_h}" xc:none \
    -fill none -stroke "#333333" -strokewidth 12 \
    -draw "roundrectangle 6,6 $((scaled_w-7)),$((scaled_h-7)) ${corner_radius},${corner_radius}" \
    /tmp/bezel_$$.png

  magick /tmp/ss_$$.png /tmp/bezel_$$.png -composite /tmp/framed_ss_$$.png

  magick "$HERO_ILLUSTRATION" -fuzz 4% -trim +repage -resize "900x620>" /tmp/hero_illustration_$$.png
  local hero_w hero_h
  read -r hero_w hero_h <<< "$(magick identify -format '%w %h' /tmp/hero_illustration_$$.png)"
  local hero_x=$(( (CANVAS_W - hero_w) / 2 ))

  magick -background none -size "1180x120" -gravity center \
    -font "$font_bold" -pointsize 74 -fill "$text_fill" \
    caption:"$keyword" /tmp/hero_keyword_$$.png

  magick -background none -size "1120x150" -gravity center \
    -font "$font_reg" -pointsize 44 -fill "$subtitle_fill" \
    caption:"$title" /tmp/hero_title_$$.png

  magick -size "${CANVAS_W}x${CANVAS_H}" "$bg_gradient" \
    /tmp/hero_keyword_$$.png -geometry "+70+104" -composite \
    /tmp/hero_title_$$.png -geometry "+100+230" -composite \
    /tmp/hero_illustration_$$.png -geometry "+${hero_x}+340" -composite \
    /tmp/framed_ss_$$.png -geometry "+${ss_x}+${ss_y}" -composite \
    -depth 8 $PNG_STRIP "$output"

  rm -f /tmp/mask_$$.png /tmp/ss_$$.png /tmp/bezel_$$.png /tmp/framed_ss_$$.png \
    /tmp/hero_illustration_$$.png /tmp/hero_keyword_$$.png /tmp/hero_title_$$.png
  echo "  -> $output"
}

compose_screenshot() {
  local key="$1" keyword="$2" title="$3" lang_dir="$4" font_bold="$5" font_reg="$6"
  local input="${SCRIPT_DIR}/${lang_dir}/${key}.png"
  local output="${SCRIPT_DIR}/${lang_dir}/${key}_framed.png"

  # Dark theme variant: dark background + white text
  local is_dark=false
  case "$key" in 08_dark_theme|05_dark_workspace) is_dark=true ;; esac

  if [ ! -f "$input" ]; then
    echo "SKIP: $input not found"
    return
  fi

  if [ "$key" = "01_session_list" ] && [ -f "$HERO_ILLUSTRATION" ]; then
    compose_hero_screenshot "$key" "$keyword" "$title" "$lang_dir" "$font_bold" "$font_reg"
    return
  fi

  # Get input dimensions
  local src_w src_h
  read -r src_w src_h <<< "$(magick identify -format '%w %h' "$input")"

  # Scale screenshot to fit with side padding
  local pad=80
  local max_w=$((CANVAS_W - pad * 2))
  local scale_ratio
  scale_ratio=$(echo "scale=6; $max_w / $src_w" | bc)
  local scaled_w=$max_w
  local scaled_h
  scaled_h=$(echo "$src_h * $scale_ratio / 1" | bc)

  # Text area at top
  local text_area_h=600

  # Cap screenshot height if it overflows
  local avail_h=$((CANVAS_H - text_area_h - 20))
  if [ "$scaled_h" -gt "$avail_h" ]; then
    scale_ratio=$(echo "scale=6; $avail_h / $src_h" | bc)
    scaled_h=$avail_h
    scaled_w=$(echo "$src_w * $scale_ratio / 1" | bc)
  fi

  local ss_x=$(( (CANVAS_W - scaled_w) / 2 ))
  local ss_y=$text_area_h

  local corner_radius=150

  echo "Composing: $key ($lang_dir)"

  # Create rounded-corner mask for screenshot
  magick -size "${scaled_w}x${scaled_h}" xc:none \
    -fill white -draw "roundrectangle 0,0 $((scaled_w-1)),$((scaled_h-1)) ${corner_radius},${corner_radius}" \
    /tmp/mask_$$.png

  # Apply mask to resized screenshot
  magick "$input" -resize "${scaled_w}x${scaled_h}" \
    /tmp/mask_$$.png -alpha off -compose CopyOpacity -composite \
    /tmp/ss_$$.png

  # Create an iPhone-like bezel (stroke around the mask)
  magick -size "${scaled_w}x${scaled_h}" xc:none \
    -fill none -stroke "#333333" -strokewidth 12 \
    -draw "roundrectangle 6,6 $((scaled_w-7)),$((scaled_h-7)) ${corner_radius},${corner_radius}" \
    /tmp/bezel_$$.png
    
  # Combine screenshot and bezel
  magick /tmp/ss_$$.png /tmp/bezel_$$.png -composite /tmp/framed_ss_$$.png

  # Compose final image with gradient background
  local bg_gradient text_fill subtitle_fill
  if [ "$is_dark" = true ]; then
    bg_gradient="gradient:#1C1C1E-#111113"
    text_fill="#F5F5F5"
    subtitle_fill="rgba(245,245,245,0.75)"
  else
    bg_gradient="gradient:#FFFFFF-#F4F4F5"
    text_fill="#111111"
    subtitle_fill="rgba(17,17,17,0.75)"
  fi

  magick -background none -size "1180x140" -gravity center \
    -font "$font_bold" -pointsize 104 -fill "$text_fill" \
    caption:"$keyword" /tmp/keyword_$$.png

  magick -background none -size "1160x170" -gravity center \
    -font "$font_reg" -pointsize 56 -fill "$subtitle_fill" \
    caption:"$title" /tmp/title_$$.png

  magick -size "${CANVAS_W}x${CANVAS_H}" "$bg_gradient" \
    /tmp/framed_ss_$$.png -geometry "+${ss_x}+${ss_y}" -composite \
    /tmp/keyword_$$.png -geometry "+70+155" -composite \
    /tmp/title_$$.png -geometry "+80+310" -composite \
    -depth 8 $PNG_STRIP "$output"

  rm -f /tmp/mask_$$.png /tmp/ss_$$.png /tmp/bezel_$$.png /tmp/framed_ss_$$.png \
    /tmp/keyword_$$.png /tmp/title_$$.png
  echo "  -> $output"
}

# Process English
echo "=== English ==="
for entry in "${SCREENSHOTS[@]}"; do
  IFS='|' read -r key kw_en tt_en kw_ja tt_ja kw_zh tt_zh kw_ko tt_ko <<< "$entry"
  compose_screenshot "$key" "$kw_en" "$tt_en" "en-US" "$FONT_EN_BOLD" "$FONT_EN_REG"
done

# Process Japanese
echo ""
echo "=== Japanese ==="
mkdir -p "${SCRIPT_DIR}/ja"
for entry in "${SCREENSHOTS[@]}"; do
  IFS='|' read -r key kw_en tt_en kw_ja tt_ja kw_zh tt_zh kw_ko tt_ko <<< "$entry"
  # Always copy latest source screenshot from en-US
  cp "${SCRIPT_DIR}/en-US/${key}.png" "${SCRIPT_DIR}/ja/${key}.png" 2>/dev/null || true
  compose_screenshot "$key" "$kw_ja" "$tt_ja" "ja" "$FONT_JA_BOLD" "$FONT_JA_REG"
done

# Process Chinese (Simplified)
echo ""
echo "=== Chinese (Simplified) ==="
mkdir -p "${SCRIPT_DIR}/zh-CN"
for entry in "${SCREENSHOTS[@]}"; do
  IFS='|' read -r key kw_en tt_en kw_ja tt_ja kw_zh tt_zh kw_ko tt_ko <<< "$entry"
  # Always copy latest source screenshot from en-US
  cp "${SCRIPT_DIR}/en-US/${key}.png" "${SCRIPT_DIR}/zh-CN/${key}.png" 2>/dev/null || true
  compose_screenshot "$key" "$kw_zh" "$tt_zh" "zh-CN" "$FONT_ZH_BOLD" "$FONT_ZH_REG"
done

# Process Korean
echo ""
echo "=== Korean ==="
mkdir -p "${SCRIPT_DIR}/ko"
for entry in "${SCREENSHOTS[@]}"; do
  IFS='|' read -r key kw_en tt_en kw_ja tt_ja kw_zh tt_zh kw_ko tt_ko <<< "$entry"
  # Always copy latest source screenshot from en-US
  cp "${SCRIPT_DIR}/en-US/${key}.png" "${SCRIPT_DIR}/ko/${key}.png" 2>/dev/null || true
  compose_screenshot "$key" "$kw_ko" "$tt_ko" "ko" "$FONT_KO_BOLD" "$FONT_KO_REG"
done

# === iPad Landscape (2752x2064) ===
IPAD_CANVAS_W=2752
IPAD_CANVAS_H=2064

compose_ipad_screenshot() {
  local key="$1" keyword="$2" title="$3" lang_dir="$4" font_bold="$5" font_reg="$6" src_dir="$7"
  local input="${SCRIPT_DIR}/${src_dir}/ipad_${key}.png"
  local output="${SCRIPT_DIR}/${lang_dir}/ipad_${key}_framed.png"

  # Dark theme variant: dark background + white text
  local is_dark=false
  case "$key" in 05_dark_workspace) is_dark=true ;; esac

  if [ ! -f "$input" ]; then
    echo "SKIP: $input not found"
    return
  fi

  local src_w src_h
  read -r src_w src_h <<< "$(magick identify -format '%w %h' "$input")"

  local pad=140
  local max_w=$((IPAD_CANVAS_W - pad * 2))
  local scale_ratio
  scale_ratio=$(echo "scale=6; $max_w / $src_w" | bc)
  local scaled_w=$max_w
  local scaled_h
  scaled_h=$(echo "$src_h * $scale_ratio / 1" | bc)

  local text_area_h=360

  local avail_h=$((IPAD_CANVAS_H - text_area_h - 20))
  if [ "$scaled_h" -gt "$avail_h" ]; then
    scale_ratio=$(echo "scale=6; $avail_h / $src_h" | bc)
    scaled_h=$avail_h
    scaled_w=$(echo "$src_w * $scale_ratio / 1" | bc)
  fi

  local ss_x=$(( (IPAD_CANVAS_W - scaled_w) / 2 ))
  local ss_y=$text_area_h

  echo "Composing iPad: ipad_$key ($lang_dir)"

  # iPad hardware bezel sizes
  local bezel_thickness=36
  local screen_w=$((scaled_w - bezel_thickness * 2))
  local screen_h=$((scaled_h - bezel_thickness * 2))
  local inner_radius=40
  local outer_radius=76

  # 1. Resize input to screen size
  local tmp_screen=/tmp/screen_$$.png
  magick "$input" -resize "${screen_w}x${screen_h}!" "$tmp_screen"

  # 2. Mask the screen for inner curves
  magick -size "${screen_w}x${screen_h}" xc:black \
    -fill white -draw "roundrectangle 0,0 $((screen_w-1)),$((screen_h-1)) ${inner_radius},${inner_radius}" \
    /tmp/inner_mask_$$.png
  magick "$tmp_screen" \( /tmp/inner_mask_$$.png -alpha off \) -compose CopyOpacity -composite /tmp/screen_masked_$$.png

  # 3. Create the outer iPad hardware bezel shape (ensure sRGB colorspace)
  local tmp_bezel=/tmp/bezel_$$.png
  magick -size "${scaled_w}x${scaled_h}" xc:none -colorspace sRGB \
    -fill "#111111" -draw "roundrectangle 0,0 $((scaled_w-1)),$((scaled_h-1)) ${outer_radius},${outer_radius}" \
    "$tmp_bezel"

  # 4. Composite the screen onto the bezel (preserve color)
  local tmp_device=/tmp/device_$$.png
  magick "$tmp_bezel" -colorspace sRGB /tmp/screen_masked_$$.png -geometry "+${bezel_thickness}+${bezel_thickness}" -composite "$tmp_device"

  # 5. Thin outline frame for realism
  magick -size "${scaled_w}x${scaled_h}" xc:none \
    -fill none -stroke "#333333" -strokewidth 4 \
    -draw "roundrectangle 2,2 $((scaled_w-3)),$((scaled_h-3)) ${outer_radius},${outer_radius}" \
    /tmp/outline_$$.png
  magick "$tmp_device" /tmp/outline_$$.png -composite "$tmp_device"

  # Compose final image with gradient background
  local bg_gradient text_fill subtitle_fill
  if [ "$is_dark" = true ]; then
    bg_gradient="gradient:#1C1C1E-#111113"
    text_fill="#F5F5F5"
    subtitle_fill="rgba(245,245,245,0.75)"
  else
    bg_gradient="gradient:#FFFFFF-#F4F4F5"
    text_fill="#111111"
    subtitle_fill="rgba(17,17,17,0.75)"
  fi

  magick -size "${IPAD_CANVAS_W}x${IPAD_CANVAS_H}" "$bg_gradient" \
    "$tmp_device" -geometry "+${ss_x}+${ss_y}" -composite \
    -gravity North \
    -font "$font_bold" -pointsize 112 -fill "$text_fill" \
    -annotate +0+110 "$keyword" \
    -font "$font_reg" -pointsize 68 -fill "$subtitle_fill" \
    -annotate +0+225 "$title" \
    -depth 8 $PNG_STRIP "$output"

  rm -f /tmp/screen_$$.png /tmp/inner_mask_$$.png /tmp/screen_masked_$$.png /tmp/bezel_$$.png /tmp/device_$$.png /tmp/outline_$$.png
  echo "  -> $output"
}

echo ""
echo "=== iPad English ==="
for entry in "${IPAD_SCREENSHOTS[@]}"; do
  IFS='|' read -r key kw_en tt_en kw_ja tt_ja kw_zh tt_zh kw_ko tt_ko <<< "$entry"
  compose_ipad_screenshot "$key" "$kw_en" "$tt_en" "en-US" "$FONT_EN_BOLD" "$FONT_EN_REG" "en-US"
done

echo ""
echo "=== iPad Japanese ==="
for entry in "${IPAD_SCREENSHOTS[@]}"; do
  IFS='|' read -r key kw_en tt_en kw_ja tt_ja kw_zh tt_zh kw_ko tt_ko <<< "$entry"
  compose_ipad_screenshot "$key" "$kw_ja" "$tt_ja" "ja" "$FONT_JA_BOLD" "$FONT_JA_REG" "en-US"
done

echo ""
echo "=== iPad Chinese (Simplified) ==="
for entry in "${IPAD_SCREENSHOTS[@]}"; do
  IFS='|' read -r key kw_en tt_en kw_ja tt_ja kw_zh tt_zh kw_ko tt_ko <<< "$entry"
  compose_ipad_screenshot "$key" "$kw_zh" "$tt_zh" "zh-CN" "$FONT_ZH_BOLD" "$FONT_ZH_REG" "en-US"
done

echo ""
echo "=== iPad Korean ==="
for entry in "${IPAD_SCREENSHOTS[@]}"; do
  IFS='|' read -r key kw_en tt_en kw_ja tt_ja kw_zh tt_zh kw_ko tt_ko <<< "$entry"
  compose_ipad_screenshot "$key" "$kw_ko" "$tt_ko" "ko" "$FONT_KO_BOLD" "$FONT_KO_REG" "en-US"
done

# === README banner (4 screenshots side by side, resized to 1200px width) ===
echo ""
echo "=== README banner ==="
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
README_IMG_DIR="${REPO_ROOT}/docs/images"
mkdir -p "$README_IMG_DIR"

README_KEYS=("01_session_list" "02_recent_sessions" "05_explorer" "06_git_actions")

for lang_dir in en-US ja zh-CN ko; do
  README_INPUTS=()
  for k in "${README_KEYS[@]}"; do
    README_INPUTS+=("${SCRIPT_DIR}/${lang_dir}/${k}_framed.png")
  done

  if [ "$lang_dir" = "en-US" ]; then
    README_OUTPUT="${README_IMG_DIR}/screenshots.png"
  else
    README_OUTPUT="${README_IMG_DIR}/screenshots-${lang_dir}.png"
  fi

  magick "${README_INPUTS[@]}" +append -resize 1200x "$README_OUTPUT"
  echo "  -> $README_OUTPUT ($(du -h "$README_OUTPUT" | cut -f1))"
done

# === Copy framed screenshots to store upload directories ===
# iOS: screenshots/store/{en-US,ja,zh-Hans,ko}/ (used by fastlane deliver)
# Android: metadata/android/{en-US,ja-JP,zh-CN,ko-KR}/images/phoneScreenshots/
echo ""
echo "=== Store upload directories ==="
STORE_DIR="${SCRIPT_DIR}/store"
ANDROID_META="${SCRIPT_DIR}/../../fastlane/metadata/android"

for lang_dir in en-US ja zh-CN ko; do
  # iOS uses zh-Hans for Simplified Chinese, while Android keeps zh-CN.
  if [ "$lang_dir" = "zh-CN" ]; then
    ios_lang="zh-Hans"
  else
    ios_lang="$lang_dir"
  fi
  store_lang_dir="${STORE_DIR}/${ios_lang}"
  mkdir -p "$store_lang_dir"
  rm -f "$store_lang_dir"/*.png
  for entry in "${SCREENSHOTS[@]}"; do
    IFS='|' read -r key _ <<< "$entry"
    f="${SCRIPT_DIR}/${lang_dir}/${key}_framed.png"
    [ -f "$f" ] || continue
    cp "$f" "$store_lang_dir/${key}.png"
  done
  for entry in "${IPAD_SCREENSHOTS[@]}"; do
    IFS='|' read -r key _ <<< "$entry"
    f="${SCRIPT_DIR}/${lang_dir}/ipad_${key}_framed.png"
    [ -f "$f" ] || continue
    cp "$f" "$store_lang_dir/ipad_${key}.png"
  done
  echo "  iOS  -> $store_lang_dir/ ($(ls "$store_lang_dir" | wc -l | tr -d ' ') files)"

  # Android metadata directory (phone screenshots only)
  if [ "$lang_dir" = "en-US" ]; then
    android_lang="en-US"
  elif [ "$lang_dir" = "ja" ]; then
    android_lang="ja-JP"
  elif [ "$lang_dir" = "ko" ]; then
    android_lang="ko-KR"
  else
    android_lang="zh-CN"
  fi
  android_ss_dir="${ANDROID_META}/${android_lang}/images/phoneScreenshots"
  mkdir -p "$android_ss_dir"
  rm -f "$android_ss_dir"/*.png
  for entry in "${SCREENSHOTS[@]}"; do
    IFS='|' read -r key _ <<< "$entry"
    f="${SCRIPT_DIR}/${lang_dir}/${key}_framed.png"
    [ -f "$f" ] || continue
    cp "$f" "$android_ss_dir/${key}.png"
  done
  echo "  Android -> $android_ss_dir/ ($(ls "$android_ss_dir" | wc -l | tr -d ' ') files)"
done

echo ""
echo "Done! Framed screenshots have '_framed' suffix."
