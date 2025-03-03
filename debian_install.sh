#!/bin/bash
#
# 安装 luacheck 及其依赖
# 适用于 Debian/Ubuntu 系统
#

# 错误处理函数
handle_error() {
    echo "错误: $1"
    exit 1
}

# 显示执行的命令
set -e  # 遇到错误时退出

# 更新软件包列表
echo "正在更新软件包列表..."
sudo apt-get update || handle_error "无法更新软件包列表"

# 安装 Lua 和开发库
echo "正在安装 Lua 及开发库..."
sudo apt-get install -y lua5.3 liblua5.3-dev luarocks || handle_error "无法安装 Lua 及开发库"

# 安装 luacheck 及其依赖
echo "正在安装 luacheck 及其依赖..."
sudo luarocks install luafilesystem || handle_error "无法安装 luafilesystem"
sudo luarocks install argparse || handle_error "无法安装 argparse"
sudo luarocks install luacheck || handle_error "无法安装 luacheck"

echo "安装完成！"
echo "您可以通过运行 'luacheck --version' 来验证安装"

# 验证安装
if command -v luacheck >/dev/null 2>&1; then
    echo "验证安装:"
    luacheck --version
else
    handle_error "luacheck 安装失败或未添加到 PATH 中"
fi