#!/bin/sh
# *****************************************************************************
# File Name: WebHookShell
# Auther: huisc
# Created Time: 2019-10-19 00:54:26
# Description:
#
#   [!].该脚本需被宝塔WebHook调用
#     1.判断由宝塔WebHook传入的参数去运行核心任务
#
#     调试：WebHookShell.sh | tee -a /tmp/HexoAuto.log
#
# *****************************************************************************

# 载入配置变量到会话
if [[ ! -f $(
    cd "$(dirname "$0")"
    pwd
)/HexoAuto.conf ]]; then
    echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: 无法找到配置文件"
    exit 1
fi
source $(
    cd "$(dirname "$0")"
    pwd
)/HexoAuto.conf

# 防止恶意访问 （大于10个进程）
if [[ $(ps -C CrontabShell.sh --no-header | wc -l) > 10 && $(ps -C WebHookShell.sh --no-header | wc -l) > 10 ]]; then
    echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: 进程数超出限制" | tee ${Path_TMP}/RunError.lock # Git仓库一旦出错需手动修复
    if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_News}"?text=进程数超出限制&desp=怀疑被攻击，程序已锁定（CrontabShell.sh/$(ps -C CrontabShell.sh --no-header | wc -l)；WebHookShell.sh/$(ps -C WebHookShell.sh --no-header | wc -l)）") -ne 200 ]]; then
        echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: ServerChan错误通知消息发送失败；进程数超出限制"
    fi
    exit 1
fi

# 主循环
Conflict_Count=0
while ((${Conflict_Count} <= ${OverTime})); do
    # 判断是否只有一个程序在运行
    if [[ $(ps -C CrontabShell.sh --no-header | wc -l)==0 && $(ps -C WebHookShell.sh --no-header | wc -l)==1 ]]; then
        # 判断是否被错误状态锁定
        if [[ ! -f ${Path_TMP}/RunError.lock ]]; then
            # 判断暂存时间文件是否存在，以当前时间创建一个时间文件
            if [[ ! -f ${Path_TMP}/WebHookShell_Pause ]]; then
                echo $(date "+%Y-%m-%d %H:%M:%S") >${Path_TMP}/WebHookShell_Pause
            fi
            # 判断缓存目录是否存在，不存在则创建
            if [[ ! -d ${Path_TMP} ]]; then
                mkdir ${Path_TMP}
            fi
            # Git WebHook
            if [[ $1 == "git_change" ]]; then
                # 由CrontabShell.sh推送的无需重复同步至本地库
                if [[ ! -f ${Path_TMP}/CrontabShell_GitPush_OK ]]; then
                    echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Info: 文章库被更新，同步至本地"
                    cd ${Path_MD}
                    git pull ${Git_URL} master:master
                    GitPull_State=$?
                fi
                if [[ ${GitPull_State} -ne 0 ]]; then
                    echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: 严重错误，文章库同步失败" | tee ${Path_TMP}/RunError.lock # Git仓库一旦出错需手动修复
                    if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_News}"?text=文章库同步失败&desp=错误发生于WebHookShell程序") -ne 200 ]]; then
                        echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: ServerChan错误通知消息发送失败；文章库同步失败" | tee ${Path_TMP}/RunError.lock
                    fi
                    exit 1
                else
                    # 切换到工作目录（两个作用：1.防止docker因volumes报错 2.防止切换目录后运行CrontabShell.sh时找不到配置文件）
                    cd ${Path_Base}
                    ${Path_Base}/CrontabShell.sh reset # 重新生成本地库样本文件
                    echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Info: 文章库同步成功"
                    # 判断暂存的时间是否小于当前时间
                    if [[ $(date -d "$(cat ${Path_TMP}/WebHookShell_Pause)" +%s) -le $(date +%s) ]]; then # 判断自动部署是否被用户暂停
                        echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Info: 发送ServerChan信息"
                        if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_TalkAdmin}"?TA_action_on=1&TA_title=检测到Gitee文章库更新&TA_content=已重新生成网页，请确认是否发布&TA_WebHookurl="${WebHook_URL}"&TA_Previewurl="${ServerChan_PreviewUrl}) == 200 ]]; then
                            echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Info: 启动预览服务器"
                            # 启动docker部署预览服务
                            docker-compose -f ${Path_Base}/docker_hexo/docker-compose_${Web_Name}-s.yml down
                            docker-compose -f ${Path_Base}/docker_hexo/docker-compose_${Web_Name}-s.yml up -d
                            if [[ $? -ne 0 ]]; then
                                echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: 启动预览服务器失败"
                                if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_News}"?text=启动预览服务器失败&desp=错误发生于WebHookShell程序") -ne 200 ]]; then
                                    echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: ServerChan错误通知消息发送失败；启动预览服务器失败" | tee ${Path_TMP}/RunError.lock
                                fi
                                exit 1
                            else
                                echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Info: 启动预览服务器成功"
                                echo $(date "+%Y-%m-%d %H:%M:%S" -d "+1 hours") >${Path_TMP}/docker-compose-s_start # Docker 服务只运行1小时，一小时后会被CrontabShell.sh程序清理
                                exit 0                                                                              # 预览逻辑正常结束
                            fi
                        else
                            echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: ServerChan预览通知信息发送失败"
                            exit 1
                        fi
                    else
                        echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Info: 自动发布被暂停至 "$(cat ${Path_TMP}/WebHookShell_Pause)
                        exit 0 # 暂停通知逻辑正常结束
                    fi
                fi
            # 发布、取消
            elif [[ $1 == "accept" || $1 == "reject" ]]; then
                echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Info: 停止预览服务器"
                # 切换到工作目录，否则docker因volumes报错
                cd ${Path_Base}
                # 停止 docker 网页预览服务
                docker-compose -f ${Path_Base}/docker_hexo/docker-compose_${Web_Name}-s.yml down
                # 允许发布
                if [[ $1 == "accept" ]]; then
                    echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Info: 部署博客"
                    docker-compose -f ${Path_Base}/docker_hexo/docker-compose_${Web_Name}-g.yml down
                    docker-compose -f ${Path_Base}/docker_hexo/docker-compose_${Web_Name}-g.yml up
                    echo $(date "+%Y-%m-%d %H:%M:%S" -d "+1 hours") >${Path_TMP}/docker-compose-g_start # Docker 服务只运行1小时，一小时后会被CrontabShell.sh程序清理
                    if [[ $? -ne 0 ]]; then
                        echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: 部署博客失败"
                        if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_News}"?text=部署博客失败&desp=错误发生于WebHookShell程序") -ne 200 ]]; then
                            echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: ServerChan错误通知消息发送失败；部署博客失败" | tee ${Path_TMP}/RunError.lock
                        fi
                        exit 1
                    else
                        echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Info: 部署博客成功"
                        exit 0 # 部署逻辑正常结束
                    fi
                fi
                exit 0 # 停止部署逻辑正常结束
            # 暂停、恢复
            elif [[ $1 == "pause" || $1 == "recovery" ]]; then
                if [[ $1 == "pause" ]]; then
                    if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_TalkAdmin}"?TA_action_on=1&TA_title=博客自动发布程序被暂停&TA_content=已暂停自动发布至"$(date "+%Y年%m月%d日%H时%M分%S秒" -d "+12 hours")${ServerChan_content}"&TA_WebHookurl="${WebHook_URL}"&TA_PreviewUrl="${ServerChan_PreviewUrl}) == 200 ]]; then
                        echo "Info: 暂停自动发布 12H"
                        echo $(date "+%Y-%m-%d %H:%M:%S" -d "+12 hours") >${Path_TMP}/WebHookShell_Pause
                        exit 0
                    else
                        echo "Error: ServerChan暂停信息发送失败"
                        exit 1
                    fi
                fi
                if [[ $1 == "recovery" ]]; then
                    echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Info: 恢复自动发布"
                    echo $(date "+%Y-%m-%d %H:%M:%S") >${Path_TMP}/WebHookShell_Pause
                    exit 0
                fi
            else
                echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: 执行参数不能为空"
                exit 0
            fi
        else
            echo $(cat ${Path_TMP}/RunError.lock)
            echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: 程序因上次运行出错导致被锁死"
            if [[ ! -f ${Path_TMP}/Errorlock ]]; then
                echo 停止服务锁定 >${Path_TMP}/Errorlock
                if [[ $(curl -sIL -w "%{http_code}" -o /dev/null ${ServerChan_News}"?text=程序因上次运行发生致命错误被锁定&desp=WebHookShell：RunError.lock") -ne 200 ]]; then
                    echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: ServerChan错误通知消息发送失败；程序因上次运行出错导致被锁死"
                fi
            fi
            exit 1
        fi
        echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: 非正常退出"
        exit 1
    fi
    sleep 1s
    let Conflict_Count++
done
echo $(date "+%Y-%m-%d %H:%M:%S")".WebHookShell.Error: 已有${Conflict}个脚本在运行，且等待超时（${Conflict_Count}/S）"
exit 1
