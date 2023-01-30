#!/bin/sh

ROOT=$(cd `dirname $0`; pwd)

PARAMS=$*

LUA_CHECK_ROOT=${ROOT}/luacheck

TMP_DIR=${ROOT}/.temp
AUTHOR_DIR=${TMP_DIR}/author
LUACHECK_OUTPUT=${TMP_DIR}/luacheck_output

rm -rf ${TMP_DIR}
mkdir -p ${AUTHOR_DIR}

# 1. 导出luacheck异常信息
# 2. 去除luacheck输出的颜色码
lua -e "package.path=\"${LUA_CHECK_ROOT}/src/?.lua;${LUA_CHECK_ROOT}/src/?/init.lua;\"..package.path" \
${LUA_CHECK_ROOT}/bin/luacheck.lua ${PARAMS} \
| sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" \
>> ${LUACHECK_OUTPUT}

# 数据汇总
brief=`cat ${LUACHECK_OUTPUT} | grep "Total: "`
echo ${brief}

# 按作者名称分文件保存
cat ${LUACHECK_OUTPUT} | grep "^\W" \
| awk -v author_dir=${AUTHOR_DIR} -F ':' '{ \
    cmd="v1=`git blame -p -L "$2","$2" "$1"|grep \"^author \"`" \
    ";author_file="author_dir"/${v1//author /}" \
    ";echo \""$0"\">>\"$author_file\"" \
    ;system(cmd) \
}'

# 检查输出的作者数量
author_count=`ls -l ${AUTHOR_DIR} | grep "^-" | wc -l`
if [ $author_count -le 0 ]; then
    # 没有异常输出 
    exit 1
fi

# 合并文件
REPORT_FILE=${ROOT}/`date +%Y-%m-%d-%H-%M-%S`-lua_check_report
# 按作者统计异常数量
printf "author\t number of warnings/errors\n" >> ${REPORT_FILE}
echo "----------------------------" >> ${REPORT_FILE}
find ${AUTHOR_DIR} -type f -exec sh -c '
    AUTHOR_DIR=$1
    name=$(basename "{}")
    file=${AUTHOR_DIR}/${name}
    count=(`wc -l "${file}"`)
    printf "%s:\t%s\n" "${name}" ${count}
' find-stat ${AUTHOR_DIR} \; >> ${REPORT_FILE}
echo ${brief} >> ${REPORT_FILE}
echo -e "\n" >> ${REPORT_FILE}
# 每个作者具体的异常项
find ${AUTHOR_DIR} -type f -exec sh -c '
    AUTHOR_DIR=$1
    name=$(basename "{}")
    echo ${name}
    cat "${AUTHOR_DIR}/${name}"
    echo -e "\n"
' find-author ${AUTHOR_DIR} \; >> ${REPORT_FILE}

echo "report file: "${REPORT_FILE}