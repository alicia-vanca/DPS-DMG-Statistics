-- 名称
name = "DPSInfo / DPS统计"
-- 版本
version = "1.2"
-- 描述
description = "ver " .. version .. [[

DPS 统计功能

p.s. 应急处理一下妥协的报错，给服务器用
p.s. 本mod功能可以关闭

]]
-- 作者
author = "胜天一猫"
-- klei官方论坛地址，为空则默认是工坊的地址
forumthread = ""
-- modicon 下一篇再介绍怎么创建的
icon_atlas = "modicon.xml"
icon = "modicon.tex"
-- dst兼容
dst_compatible = true
-- 是否是客户端mod
client_only_mod = false
-- 是否是所有客户端都需要安装
all_clients_require_mod = true
-- 饥荒api版本，固定填10
api_version = 10
priority = 1000

-- mod的配置项，后面介绍
configuration_options = {
    {
        name = "func_open",
        label = "开关",
        hover = "功能总开关",
        options = {
            {data = "open", description = "打开/open"},
            {data = "close", description = "关闭/close"},
        },
        default = "open",
    },
    {
        name = "dps_offset",
        label = "偏移",
        hover = "伤害统计偏移位置",
        options = {
            {data = "middle", description = "中间/middle"},
            {data = "right", description = "左右/right"},
            {data = "up", description = "上下/up"},
            {data = "no", description = "无/no"},
        },
        default = "right",
    },
    {
        name = "dps_end",
        label = "死后宣告",
        hover = "是否在击杀后显示总结统计",
        options = {
            {data = "near", description = "附近"},
            {data = "all", description = "全局"},
            {data = "no", description = "否"},
        },
        default = "near",
    },
}