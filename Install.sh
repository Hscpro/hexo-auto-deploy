#!/bin/sh
# *****************************************************************************
# File Name: Install
# Auther: huisc
# Created Time: 2019-10-19 00:54:26
# Description:
#
#     1.自动生成文章、Pages的GIT访问密钥
#     2.将本地的文章仓库与远程仓库关联起来
#     3.根据配置生成 Docker 部署文件
#
# *****************************************************************************

# 载入配置变量到会话
if [[ ! -f $(
    cd "$(dirname "$0")"
    pwd
)/HexoAuto.conf ]]; then
    echo $(date "+%Y-%m-%d %H:%M:%S")".Init.Error: 无法找到配置文件"
    exit 1
fi
source $(
    cd "$(dirname "$0")"
    pwd
)/HexoAuto.conf

# 密钥生成
if [[ $1 == "keys-ww" || $1 == "keys-md" ]]; then
    if [[ $1 == "keys-ww" ]]; then
        pathssh=${Path_Base}
        githost=${Gitww_Host}
        gitport=${Gitww_Port}
    elif [[ $1 == "keys-md" ]]; then
        pathssh="/root"
        githost=${Git_Host}
        gitport=${Git_Port}
    fi
    # .ssh文件夹创建
    if [[ ! -d ${pathssh}/.ssh ]]; then
        mkdir ${pathssh}/.ssh
        chmod 700 ${pathssh}/.ssh
        chown root:root ${pathssh}/.ssh
    fi
    # 密钥创建
    if [[ ! -f ${pathssh}/.ssh/${githost}_keys ]]; then
        ssh-keygen -t rsa -N '' -f ${pathssh}/.ssh/${githost}_keys -q -b 2048
    fi
    cat <<EOF >>${pathssh}/.ssh/config
Host ${githost}
	HostName ${githost}
    Port ${gitport}
    StrictHostKeyChecking no
	IdentityFile ${pathssh}/.ssh/${githost}_keys
EOF
    if [[ ! -f ${pathssh}/.ssh/config ]]; then
        chmod 644 ${pathssh}/.ssh/config
        chown root:root ${pathssh}/.ssh/config
    fi
    echo $(date "+%Y-%m-%d %H:%M:%S")".Init.Info: 请将下面的密钥拷贝至${githost}"
    cat ${pathssh}/.ssh/${githost}_keys.pub
# 仓库关联
elif [[ $1 == "git-push" || $1 == "git-clone" ]]; then
    # 以本地库为基准创建关联
    if [[ $1 == "git-push" ]]; then
        if [[ ! -d ${Path_MD} ]]; then
            mkdir ${Path_MD}
        fi
        cd ${Path_MD}
        git init
        git config user.name ${Git_Name}
        git config user.email ${Git_Email}
        git add .
        git commit -m "Initialization"
        git remote add origin ${Git_URL}
        git push -u ${Git_URL} master
    # 以远程库为基准创建关联
    elif [[ $1 == "git-clone" ]]; then
        cd ${Path_Base}
        git config user.name ${Git_Name}
        git config user.email ${Git_Email}
        git clone ${Git_URL}
        git remote add origin ${Git_URL}
    fi
elif [[ $1 == "docker" ]]; then
    if [[ ! -d ${Path_Base}/docker_hexo ]]; then
        mkdir ${Path_Base}/docker_hexo
    fi
#----------------------------------------------------------------------------------------
echo $(date "+%Y-%m-%d %H:%M:%S")".Init.Info: 生成 Docker 镜像模板"
    cat <<EOF >${Path_Base}/docker_hexo/Dockerfile_${Web_Name}
# *****************************************************************************
# File Name: Dockerfile
# Auther: huisc
# Created Time: 2019-10-19 00:54:26
# Description:
#
#     Hexo Blog: https://www.hscbook.com
#
# *****************************************************************************

# 基础镜像
#FROM node:10
FROM mhart/alpine-node:10

# 维护者信息
MAINTAINER huisc

# 容器工作目录
WORKDIR /hexo

# FROM mhart/alpine-node:10 环境初始化
RUN apk --update --no-progress add git openssh libtool zlib zlib-dev libpng automake autoconf nasm gcc make gawk g++

# 安装Hexo
RUN npm install hexo-cli -g
RUN hexo init .
RUN npm install

## 渲染（maupassant主题依赖）
RUN npm install hexo-renderer-pug --save
RUN npm install hexo-renderer-sass --save
## 字数统计（maupassant主题依赖）
RUN npm install hexo-wordcount
## 搜索（maupassant主题依赖）
RUN npm install hexo-generator-search --save
## Sitemap
RUN npm install hexo-generator-sitemap --save
RUN npm install hexo-generator-baidu-sitemap --save
## RSS订阅
RUN npm install hexo-generator-feed --save
## 二维码生成
RUN npm install hexo-helper-qrcode --save
## 压缩组件
RUN npm install hexo-all-minifier --save
## nofollow
RUN npm install hexo-filter-nofollow --save
## 流程图
RUN npm install hexo-filter-flowchart --save
## 部署GIT
RUN npm install hexo-deployer-git --save

# 清理
RUN rm /hexo/scaffolds -r
RUN rm /hexo/source -r
RUN rm /hexo/themes -r
RUN mv /hexo/_config.yml /hexo/_config.yml.install.bak

# 设置git
RUN git config --global user.name "${Gitww_Name}"
RUN git config --global user.email "${Gitww_Email}"

# 创建挂载点
VOLUME ["/hexo/scaffolds", "/hexo/source", "/hexo/themes", "/root/.ssh"]

# 映射端口
EXPOSE 4000

# 运行命令
CMD ["/bin/bash"]
EOF
#----------------------------------------------------------------------------------------
    echo $(date "+%Y-%m-%d %H:%M:%S")".Init.Info: 生成预览服务启动模板"
    cat <<EOF >${Path_Base}/docker_hexo/docker-compose_${Web_Name}-s.yml
version: '3'
services:
    blog_${Web_Name}:
        build:
            context: .
            dockerfile: Dockerfile_${Web_Name}
        image: hexo:${Web_Name}
        container_name: blog_${Web_Name}_s
        command: sh -c 'hexo clean && hexo server'
        ports:
         - "8080:4000"
        volumes:
         - ${Path_Base}/.ssh:/root/.ssh
         - ${Path_MD}/scaffolds:/hexo/scaffolds
         - ${Path_MD}/source:/hexo/source
         - ${Path_MD}/themes:/hexo/themes
         - ${Path_MD}/_config.yml:/hexo/_config.yml

EOF
#----------------------------------------------------------------------------------------
    echo $(date "+%Y-%m-%d %H:%M:%S")".Init.Info: 生成部署服务启动模板"
    cat <<EOF >${Path_Base}/docker_hexo/docker-compose_${Web_Name}-g.yml
version: '3'
services:
    blog_${Web_Name}:
        build:
            context: .
            dockerfile: Dockerfile_${Web_Name}
        image: hexo:${Web_Name}
        container_name: blog_${Web_Name}_g
        command: sh -c '(rm /hexo/.deploy_git -r || true) && hexo clean && hexo generate -d'
        ports:
         - "4000:4000"
        volumes:
         - ${Path_Base}/.ssh:/root/.ssh
         - ${Path_MD}/scaffolds:/hexo/scaffolds
         - ${Path_MD}/source:/hexo/source
         - ${Path_MD}/themes:/hexo/themes
         - ${Path_MD}/_config.yml:/hexo/_config.yml

EOF
#----------------------------------------------------------------------------------------
else
    echo "请输入选项："
    echo .
    echo "  keys-ww：生成远程Pages仓库SSH密钥"
    echo "  keys-md：生成远程文章仓库SSH密钥"
    echo "  git-push：以本地文章库为基准关联远程文章库"
    echo "  git-clone：以远程文章库为基准关联本地文章库"
    echo "  docker：生成docker镜像部署文件以及启动文件"
    echo .
    exit 0
fi
