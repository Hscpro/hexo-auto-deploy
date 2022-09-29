#!/bin/sh
# *****************************************************************************
# File Name: CrontabShell
# Auther: huisc
# Created Time: 2019-10-19 00:54:26
# Description:
#
#   [!].该脚本被需Crontab定时调用（5分钟-10分钟）
#     1.WebHookShell.sh 定时事物处理
#     2.GIT初始化、密钥生成
#     3.检查本地文章库是否发生改变，若被改动则push到仓库并由WebHookShell.sh执行发
#
#     调试：CrontabShell.sh | tee -a /tmp/HexoAuto.log
#
# *****************************************************************************

# 载入配置变量到会话
if [[ ! -f $(
    cd "$(dirname "$0")"
    pwd
)/HexoAuto.conf ]]; then
    echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: 无法找到配置文件"
    exit 1
fi
source $(
    cd "$(dirname "$0")"
    pwd
)/HexoAuto.conf

# 防止恶意访问 （大于10个进程）
if [[ $(ps -C CrontabShell.sh --no-header | wc -l) > 10 && $(ps -C WebHookShell.sh --no-header | wc -l) > 10 ]]; then
    echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: 进程数超出限制" | tee ${Path_TMP}/RunError.lock # Git仓库一旦出错需手动修复
    if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_News}"?text=进程数超出限制&desp=怀疑被攻击，程序已锁定（CrontabShell.sh/$(ps -C CrontabShell.sh --no-header | wc -l)；WebHookShell.sh/$(ps -C WebHookShell.sh --no-header | wc -l)）") -ne 200 ]]; then
        echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: ServerChan错误通知消息发送失败；进程数超出限制"
    fi
    exit 1
fi

# 验证文件清理函数
ClearCheck() {
    cat /dev/null >${Path_TMP}/CheckFile_${1}.log
}
# 验证文件生成函数（全局排除文件夹下的 “.git” 文件夹）
# 枚举每个文件并生成 MD5
CheckFile() {
    for i in ${CheckDir[@]}; do
        find ${i} -type f -name "*" ! -path "${i}/.git/*" -print0 | xargs -0 md5sum >>${Path_TMP}/CheckFile_${1}.log # 文件名若包含空格会报错解决方法： -print0 参数将空格转换为“null”  -0 参数将“null”重新转换为空格
    done
}

# 执行清理选项
if [[ $1 == "reset" ]]; then
    # 假如验证文件目录、文件不存在则创建
    if [[ ! -d ${Path_TMP} ]]; then
        echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Info: 验证文件不存在，无需清理"
    else # 由于 WebHookShell 同步操作改动了目录，重新生成验证文件以防重复推送导致GIT冲突
        ClearCheck "New"
        ClearCheck "Old"
        CheckFile "Old"
        exit 0
    fi
else
    # 主循环
    Conflict_Count=0
    while ((${Conflict_Count} <= ${OverTime})); do
        # 判断是否只有一个程序在运行
        if [[ $(ps -C CrontabShell.sh --no-header | wc -l)==1 && $(ps -C WebHookShell.sh --no-header | wc -l)==0 ]]; then
            # 判断是否被错误状态锁定
            if [[ ! -f ${Path_TMP}/RunError.lock ]]; then
                # 定期清理 Docker 程序（两个作用：1.防止因为程序出错导致的资源占用 2.防止WebHookShell生成预览服务后未确认生成导致服务长期运行）
                if [[ (-f ${Path_TMP}/docker-compose-s_start) && ($(date -d "$(cat ${Path_TMP}/docker-compose-s_start)" +%s) -le $(date +%s)) ]]; then
                    rm ${Path_TMP}/docker-compose-s_start
                    docker-compose -f ${Path_Base}/docker_hexo/docker-compose_${Web_Name}-s.yml down
                fi
                if [[ (-f ${Path_TMP}/docker-compose-g_start) && $(date -d "$(cat ${Path_TMP}/docker-compose-g_start)" +%s) -le $(date +%s) ]]; then
                    rm ${Path_TMP}/docker-compose-g_start
                    docker-compose -f ${Path_Base}/docker_hexo/docker-compose_${Web_Name}-g.yml down
                fi
                # 假如本地文章库没有关联Git
                if [[ ! -d ${Path_MD}/.git ]]; then
                    echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: 未创建GIT" | tee ${Path_TMP}/RunError.lock
                    if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_News}"?text=文章库.GIT不存在&desp=错误发生于CrontabShell程序") -ne 200 ]]; then
                        echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: ServerChan错误通知消息发送失败"
                    fi
                else
                    # 假如验证文件目录、文件不存在则创建
                    if [[ ! -d ${Path_TMP} ]]; then
                        mkdir ${Path_TMP}
                    fi
                    if [[ ! -f ${Path_TMP}/CheckFile_Old.log ]]; then
                        CheckFile "Old"
                    fi
                    # 生成新验证日志
                    CheckFile "New"
                    # 新验证日志与样本日志进行比较 > 结果输出到 Diff_Return
                    /usr/bin/diff ${Path_TMP}/CheckFile_New.log ${Path_TMP}/CheckFile_Old.log >${Path_TMP}/CheckFile_Diff.log
                    Diff_Return=$?
                    # 清除新旧日志，并重新生成样本日志
                    ClearCheck "New"
                    ClearCheck "Old"
                    CheckFile "Old"
                    # 假如比较结果有变化
                    if [[ ${Diff_Return} -ne 0 ]]; then
                        echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Info: 文件发生改动，推送至文章库Git"
                        cd ${Path_MD}
                        git add .
                        git commit -m "$(date '+CrontabShell_%Y-%m-%d_%H:%M:%S')"
                        git push ${Git_URL} master
                        if [[ $? -ne 0 ]]; then
                            echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: 文件推送至文章库失败" | tee ${Path_TMP}/RunError.lock
                            if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_News}"?text=文件推送至文章库失败&desp=错误发生于CrontabShell程序") -ne 200 ]]; then
                                echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: ServerChan错误通知消息发送失败；文件推送至文章库失败" | tee ${Path_TMP}/RunError.lock
                            fi
                            exit 1
                        else
                            echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Info: 文件推送至文章库成功" | tee ${Path_TMP}/CrontabShell_GitPush_OK
                            exit 0
                        fi
                    # 比对结果无变化，正常结束
                    else
                        exit 0
                    fi
                fi
            else
                echo $(cat ${Path_TMP}/RunError.lock)
                echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: 程序因上次运行出错导致被锁死"
                if [[ ! -f ${Path_TMP}/Errorlock ]]; then
                    echo 停止服务锁定 >${Path_TMP}/Errorlock
                    if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_News}"?text=程序因上次运行发生致命错误被锁定&desp=CrontabShell：RunError.lock") -ne 200 ]]; then
                        echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: ServerChan错误通知消息发送失败；程序因上次运行出错导致被锁死"
                    fi
                fi
                exit 1
            fi
            echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: 非正常退出"
            exit 1
        fi
        sleep 1s
        let Conflict_Count++
    done
    echo $(date "+%Y-%m-%d %H:%M:%S")".CrontabShell.Error: 已有${Conflict}个脚本在运行，且等待超时（${Conflict_Count}/S）"
    exit 1
fi
