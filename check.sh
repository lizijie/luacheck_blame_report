#!/bin/bash

# luacheck_blame_report 脚本
# 自动检测项目使用的版本控制系统类型（Git或SVN）
# 执行luacheck并生成按作者分类的报告

ROOT=$(cd `dirname $0`; pwd)
PARAMS=$*

LUA_CHECK_ROOT=${ROOT}/luacheck

TMP_DIR=${ROOT}/.temp
AUTHOR_DIR=${TMP_DIR}/author
LUACHECK_OUTPUT=${TMP_DIR}/luacheck_output

# 清理临时目录
rm -rf ${TMP_DIR}
mkdir -p ${AUTHOR_DIR}

# 自动检测版本控制系统类型
detect_vcs_type() {
    local target_dir=$1
    
    # 检查是否为Git仓库
    if [ -d "${target_dir}/.git" ] || git rev-parse --git-dir > /dev/null 2>&1; then
        echo "git"
        return 0
    fi
    
    # 检查是否为SVN仓库
    if [ -d "${target_dir}/.svn" ] || svn info > /dev/null 2>&1; then
        echo "svn"
        return 0
    fi
    
    # 默认返回空，表示未检测到版本控制系统
    echo ""
    return 1
}

# 从参数中提取目标目录（通常是第一个非选项参数）
TARGET_DIR=""
for param in ${PARAMS}; do
    # 使用兼容/bin/sh的方式检查参数是否以'-'开头
    first_char=`echo "$param" | cut -c1`
    if [ "$first_char" != "-" ] && [ -d "$param" ]; then
        TARGET_DIR="$param"
        break
    fi
done

# 如果未找到目标目录，则使用当前目录
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="."
fi

# 获取目标目录的绝对路径
TARGET_DIR_ABS=$(cd "$TARGET_DIR" && pwd)

# 检测版本控制系统类型
VCS_TYPE=$(detect_vcs_type "$TARGET_DIR")
echo "检测到版本控制系统类型: $VCS_TYPE"

# 如果未检测到支持的版本控制系统，则退出
if [ -z "$VCS_TYPE" ]; then
    echo "未检测到支持的版本控制系统（Git或SVN）"
    echo "请确保项目在Git或SVN仓库中"
    exit 2
fi

# 1. 导出luacheck异常信息
# 2. 去除luacheck输出的颜色码
luacheck ${PARAMS} | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" >> ${LUACHECK_OUTPUT}

# 数据汇总
brief=`cat ${LUACHECK_OUTPUT} | grep -a "Total: " 2>/dev/null`
echo ${brief}

# 按作者名称分文件保存
cat ${LUACHECK_OUTPUT} | grep -a "^\W" 2>/dev/null | \
awk -v author_dir=${AUTHOR_DIR} -v vcs_type=${VCS_TYPE} -v target_dir=${TARGET_DIR_ABS} -F ':' '{
    # 去除文件路径前后的空格
    file_path = $1;
    gsub(/^[ \t]+|[ \t]+$/, "", file_path);
    
    # 尝试不同的文件路径组合
    original_path = file_path;
    found_file = 0;
    
    # 1. 直接使用原始路径
    if (system("test -f \"" file_path "\"") == 0) {
        found_file = 1;
    } 
    # 2. 尝试添加目标目录前缀
    else if (system("test -f \"" target_dir "/" file_path "\"") == 0) {
        file_path = target_dir "/" file_path;
        found_file = 1;
    }
    # 3. 如果文件路径包含目标目录名，尝试从目标目录开始的相对路径
    else {
        # 获取目标目录的基本名称（不包含路径）
        cmd = "basename \"" target_dir "\"";
        cmd | getline target_basename;
        close(cmd);
        
        # 查找目标目录名在文件路径中的位置
        idx = index(file_path, target_basename);
        if (idx > 0) {
            # 从目标目录名开始截取路径
            rel_path = substr(file_path, idx);
            if (system("test -f \"" target_dir "/../" rel_path "\"") == 0) {
                file_path = target_dir "/../" rel_path;
                found_file = 1;
            }
        }
    }
    
    if (!found_file) {
        next;
    }
    
    # 根据版本控制系统类型获取作者信息
    if (vcs_type == "git") {
        # 获取文件所在目录
        file_dir = file_path;
        gsub(/\/[^\/]*$/, "", file_dir);
        if (file_dir == file_path) file_dir = ".";
        
        # 获取文件名
        file_name = file_path;
        gsub(/^.*\//, "", file_name);
        
        # 在文件所在目录执行git blame
        cmd = "cd \"" file_dir "\" && git blame -p -L " $2 "," $2 " \"" file_name "\" 2>/dev/null | grep -a \"^author \" 2>/dev/null | sed \"s/author //\" || echo \"未知作者\"";
        cmd | getline author;
        close(cmd);
    } else if (vcs_type == "svn") {
        # 获取文件所在目录
        file_dir = file_path;
        gsub(/\/[^\/]*$/, "", file_dir);
        if (file_dir == file_path) file_dir = ".";
        
        # 获取文件名
        file_name = file_path;
        gsub(/^.*\//, "", file_name);
        
        # 首先检查文件是否在SVN版本控制中
        check_cmd = "cd \"" file_dir "\" && svn info \"" file_name "\" > /dev/null 2>&1";
        if (system(check_cmd) != 0) {
            author = "未版本控制";
        } else {
            cmd = "cd \"" file_dir "\" && svn blame \"" file_name "\" 2>/dev/null | head -" $2 " | tail -1";
            cmd | getline author;
            close(cmd);
            
            # 提取作者名（第二个字段）
            if (author != "") {
                split(author, fields, " ");
                author = fields[2];
            } else {
                author = "未知作者";
            }
        }
    }
    
    if (author != "") {
        author_file = author_dir "/" author;
        print $0 >> author_file;
        close(author_file);
    }
}'

# 检查输出的作者数量
author_count=`ls -l ${AUTHOR_DIR} | grep -a "^-" 2>/dev/null | wc -l`

if [ $author_count -le 0 ]; then
    # 没有异常输出 
    echo "未找到任何作者信息，请检查文件路径和版本控制系统"
    exit 1
fi

# 合并文件
REPORT_FILE=${ROOT}/`date +%Y-%m-%d-%H-%M-%S`-lua_check_report
# 按作者统计异常数量
printf "author\t number of warnings/errors\n" >> ${REPORT_FILE}
echo "----------------------------" >> ${REPORT_FILE}
find ${AUTHOR_DIR} -type f -exec bash -c '
    AUTHOR_DIR=$1
    name=$(basename "{}")
    file=${AUTHOR_DIR}/${name}
    count=(`wc -l "${file}"`)
    printf "%s:\t%s\n" "${name}" ${count}
' find-stat ${AUTHOR_DIR} \; >> ${REPORT_FILE}
echo ${brief} >> ${REPORT_FILE}
echo -e "\n" >> ${REPORT_FILE}
# 每个作者具体的异常项
find ${AUTHOR_DIR} -type f -exec bash -c '
    AUTHOR_DIR=$1
    name=$(basename "{}")
    echo ${name}
    cat "${AUTHOR_DIR}/${name}"
    echo -e "\n"
' find-author ${AUTHOR_DIR} \; >> ${REPORT_FILE}

echo "report file: "${REPORT_FILE}