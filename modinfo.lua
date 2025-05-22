-- Version
version = "1.2_00"
-- Name
name = "DPS/DMG Statistics v" .. version
-- Description
description = [[
 
Damage Per Second & Total Damage Statistics
(only apply to Epic Bosses)

Translated & Modified for persional use.

Original mod: [ DPSInfo/ DPS统计 ] by [ 胜天一猫 ]
https://steamcommunity.com/sharedfiles/filedetails/?id=3304784351

]]
-- Author
author = "胜天一猫 | Modified by VanCa"
-- Klei official forum address, defaults to the workshop address if empty
forumthread = ""
-- Modicon, will introduce how to create it in the next article
icon_atlas = "modicon.xml"
icon = "modicon.tex"
-- DST compatible
dst_compatible = true
-- Is this a client-side mod
client_only_mod = false
-- Does every client need to install this mod
all_clients_require_mod = true
-- Hunger Games API version, fixed at 10
api_version = 10
priority = 1000

-- Mod configuration options, will be introduced later
configuration_options = {
    {
        name = "func_open",
        label = "Main switch",
        hover = "Turn this mod on or off",
        options = {
            {data = "open", description = "On"},
            {data = "close", description = "Off"},
        },
        default = "open",
    },
    {
        name = "dps_offset",
        label = "Statistics position in combat",
        hover = "DPS statistics offset position while in combat",
        options = {
            {data = "head", description = "Boss's head"},
            {data = "left_right", description = "Boss's left/right"},
            {data = "under", description = "Under boss"},
            {data = "no", description = "None"},
        },
        default = "no",
    },
    {
        name = "dps_end",
        label = "Statistics after boss dead",
        hover = "Whether to display summary statistics after boss dead",
        options = {
            {data = "near", description = "Nearby players"},
            {data = "all", description = "Global"},
            {data = "no", description = "No"},
        },
        default = "near",
    },
    {
        name = "dps_players_only",
        label = "Top attackers are",
        hover = "Whether to display mobs/fire's damage in top attackers list",
        options = {
            {data = true, description = "Players only"},
            {data = false, description = "All factors"}
        },
        default = false,
    },
    {
        name = "enable_debug_mode",
        label = "Debug mode",
        hover = "Whether to write debug logs",
        options = {
            {data = true, description = "On"},
            {data = false, description = "Off"}
        },
        default = false,
    }
}