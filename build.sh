#!/bin/bash

# =============================================================================
# Diarum (吾身) - 懒猫云应用构建和发布脚本
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 应用信息
APP_NAME="Diarum"
APP_PACKAGE="cloud.lazycat.app.diarum"
MANIFEST_FILE="lzc-manifest.yml"
BUILD_FILE="lzc-build.yml"

# 获取版本号
get_version() {
    grep "^version:" "$MANIFEST_FILE" | awk '{print $2}' | tr -d '"'
}

# 打印函数
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查必要文件
check_files() {
    print_info "检查必要文件..."

    local missing=0

    if [[ ! -f "$MANIFEST_FILE" ]]; then
        print_error "缺少 $MANIFEST_FILE"
        missing=1
    fi

    if [[ ! -f "$BUILD_FILE" ]]; then
        print_error "缺少 $BUILD_FILE"
        missing=1
    fi

    if [[ ! -f "icon.png" ]]; then
        print_warning "缺少 icon.png (512x512 PNG)"
        print_info "请提供应用图标后再构建"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        return 1
    fi

    print_success "所有必要文件已就绪"
    return 0
}

# 检查登录状态
check_login() {
    print_info "检查懒猫应用商店登录状态..."
    if ! lzc-cli appstore my-images &> /dev/null 2>&1; then
        print_warning "未登录懒猫应用商店"
        print_info "请先执行: lzc-cli appstore login"
        return 1
    fi
    print_success "已登录懒猫应用商店"
    return 0
}

# 显示应用信息
show_info() {
    echo ""
    echo "=============================================="
    echo "  $APP_NAME 应用信息"
    echo "=============================================="
    echo ""
    echo "包名: $APP_PACKAGE"
    echo "版本: $(get_version)"
    echo ""
    echo "配置文件:"
    echo "  - $MANIFEST_FILE"
    echo "  - $BUILD_FILE"
    echo ""

    if [[ -f "icon.png" ]]; then
        echo "图标: icon.png ✓"
    else
        echo "图标: icon.png ✗ (缺失)"
    fi
    echo ""

    # 显示镜像信息
    local image=$(grep "image:" "$MANIFEST_FILE" | head -1 | awk '{print $2}')
    echo "Docker 镜像: $image"
    echo ""
}

# 构建应用
build_app() {
    print_info "开始构建应用..."

    if ! check_files; then
        return 1
    fi

    local version=$(get_version)
    local output_file="${APP_NAME,,}-${version}.lpk"

    print_info "构建版本: $version"
    print_info "输出文件: $output_file"

    if lzc-cli project build -o "$output_file"; then
        print_success "构建成功: $output_file"
        ls -lh "$output_file"
        return 0
    else
        print_error "构建失败"
        return 1
    fi
}

# 复制镜像到懒猫仓库
copy_image() {
    print_info "复制镜像到懒猫仓库..."

    if ! check_login; then
        return 1
    fi

    # 获取原始镜像
    local original_image=$(grep "image:" "$MANIFEST_FILE" | head -1 | awk '{print $2}')

    if [[ -z "$original_image" ]]; then
        print_error "无法从 manifest 中获取镜像信息"
        return 1
    fi

    print_info "原始镜像: $original_image"

    # 检查是否已经是懒猫仓库镜像
    if [[ "$original_image" == registry.lazycat.cloud/* ]]; then
        print_info "镜像已在懒猫仓库中，跳过复制"
        return 0
    fi

    print_info "正在复制镜像到懒猫仓库..."

    # 执行复制并捕获输出
    local result
    result=$(lzc-cli appstore copy-image "$original_image" 2>&1)
    local exit_code=$?

    echo "$result"

    if [[ $exit_code -ne 0 ]]; then
        print_error "镜像复制失败"
        return 1
    fi

    # 提取新镜像地址
    local new_image=$(echo "$result" | grep "^uploaded:" | awk '{print $2}')

    if [[ -z "$new_image" ]]; then
        print_error "无法从输出中提取新镜像地址"
        return 1
    fi

    print_success "新镜像: $new_image"

    # 更新 manifest 文件
    update_manifest_image "$original_image" "$new_image"

    return 0
}

# 更新 manifest 中的镜像
update_manifest_image() {
    local old_image="$1"
    local new_image="$2"

    print_info "更新 manifest 文件中的镜像..."

    # 备份原文件
    cp "$MANIFEST_FILE" "${MANIFEST_FILE}.bak"

    # 使用 sed 更新镜像，并保留原始镜像作为注释
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|image: ${old_image}|image: ${new_image}\n      # Original: ${old_image}|g" "$MANIFEST_FILE"
    else
        # Linux
        sed -i "s|image: ${old_image}|image: ${new_image}\n      # Original: ${old_image}|g" "$MANIFEST_FILE"
    fi

    print_success "manifest 文件已更新"
    print_info "备份文件: ${MANIFEST_FILE}.bak"
}

# 发布到应用商店
publish_app() {
    print_info "发布到懒猫应用商店..."

    if ! check_login; then
        return 1
    fi

    local version=$(get_version)
    local lpk_file="${APP_NAME,,}-${version}.lpk"

    if [[ ! -f "$lpk_file" ]]; then
        print_error "找不到 lpk 文件: $lpk_file"
        print_info "请先执行构建"
        return 1
    fi

    print_info "发布文件: $lpk_file"

    if lzc-cli appstore publish "$lpk_file"; then
        print_success "发布成功！"
        print_info "请等待审核（通常 1-3 天）"
        return 0
    else
        print_error "发布失败"
        return 1
    fi
}

# 一键发布
one_click_publish() {
    echo ""
    echo "=============================================="
    echo "  一键构建 + 镜像复制 + 发布"
    echo "=============================================="
    echo ""

    # 阶段 1: 初始构建
    print_info "阶段 1/4: 初始构建..."
    if ! build_app; then
        print_error "初始构建失败，中止流程"
        return 1
    fi

    echo ""

    # 阶段 2: 镜像复制
    print_info "阶段 2/4: 镜像复制..."
    read -p "是否需要复制镜像到懒猫仓库？(y/n): " copy_choice
    if [[ "$copy_choice" == "y" || "$copy_choice" == "Y" ]]; then
        if ! copy_image; then
            print_error "镜像复制失败，中止流程"
            return 1
        fi

        echo ""

        # 阶段 3: 重新构建
        print_info "阶段 3/4: 使用新镜像重新构建..."
        if ! build_app; then
            print_error "重新构建失败，中止流程"
            return 1
        fi
    else
        print_info "跳过镜像复制"
        print_info "阶段 3/4: 跳过（无需重新构建）"
    fi

    echo ""

    # 阶段 4: 发布
    print_info "阶段 4/4: 发布到应用商店..."
    read -p "是否发布到应用商店？(y/n): " publish_choice
    if [[ "$publish_choice" == "y" || "$publish_choice" == "Y" ]]; then
        if ! publish_app; then
            print_error "发布失败"
            return 1
        fi
    else
        print_info "跳过发布"
    fi

    echo ""
    print_success "流程完成！"
}

# 显示菜单
show_menu() {
    echo ""
    echo "=============================================="
    echo "  $APP_NAME 构建和发布工具"
    echo "=============================================="
    echo ""
    echo "  1. 构建应用 (Build)"
    echo "  2. 复制镜像到懒猫仓库 (Copy Image)"
    echo "  3. 发布到应用商店 (Publish)"
    echo "  4. 一键构建+镜像复制+发布 (One-Click)"
    echo "  5. 查看应用信息 (Info)"
    echo "  6. 退出"
    echo ""
}

# 主函数
main() {
    while true; do
        show_menu
        read -p "请选择操作 (1-6): " choice

        case $choice in
            1)
                build_app
                ;;
            2)
                copy_image
                ;;
            3)
                publish_app
                ;;
            4)
                one_click_publish
                ;;
            5)
                show_info
                ;;
            6)
                print_info "再见！"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 1-6"
                ;;
        esac
    done
}

# 运行
main
