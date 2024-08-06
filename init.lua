--
-- Minetest verbana GUI
--
-- Copyright © 2023 by luk3yx
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--

local gui = flow.widgets
local data = verbana.data
local settings = verbana.settings
local lib_asn = verbana.lib_asn
local lib_ip = verbana.lib_ip
local util = verbana.util

local S = minetest.get_translator("verbana_gui")
local HOME, PLAYER, IP, ASN, REPORTS = 1, 2, 3, 4, 5
local mode_labels = {S("Home"), S("Player"), S("IP"), S("ASN"), S("Reports")}

local function status_color(status_id, name)
    return minetest.colorize(data.player_status_color[status_id] or
        data.player_status.default.color, name)
end

local function get_status_name(status_id)
    return status_color(status_id, data.player_status_name[status_id] or
        data.player_status.default.name)
end

local function ip_status_color(status_id, name)
    return minetest.colorize(data.ip_status_color[status_id] or
        data.ip_status.default.color, name)
end

local function get_ip_status_name(status_id)
    return status_color(status_id, data.ip_status_name[status_id] or
        data.ip_status.default.name)
end

local function asn_status_color(status_id, name)
    return minetest.colorize(data.asn_status_color[status_id] or
        data.asn_status.default.color, name)
end

local function get_asn_status_name(status_id)
    return status_color(status_id, data.asn_status_name[status_id] or
        data.asn_status.default.name)
end

local function expired(status)
    if status and status.expires and os.time() >= status.expires then
        return minetest.colorize("grey", S(" (expired)"))
    end
    return ""
end

local function player_list(list)
    if #list == 0 then
        return gui.Label{label = S("No players found")}
    end

    local vbox = {name = "player_list", h = 3, expand = true}
    for i, row in ipairs(list) do
        local pname = row.player_name
        local n = "player_list" .. i
        vbox[#vbox + 1] = gui.Button{
            name = n,
            label = status_color(row.player_status_id, pname),
            h = 0.6,
            on_event = function(_, ctx)
                ctx.form.tab = PLAYER
                ctx.form.player = pname
                return true
            end,
        }
        vbox[#vbox + 1] = gui.Tooltip{
            gui_element_name = n,
            tooltip_text = S("Status: @1@2",
                get_status_name(row.player_status_id), ""),
        }
    end
    return gui.ScrollableVBox(vbox)
end

local function status_log(log, name, show_target_player, show_more)
    local vbox = {name = name, h = 3, expand = true}
    for i, row in ipairs(log) do
        local ts = os.date("%Y-%m-%d", row.timestamp)
        local s = name == "ip_status" and get_ip_status_name(row.status_id) or
            get_status_name(row.status_id)
        local msg
        local target = row.player_name
        if show_target_player then
            msg = S("@1: @2 set status of @3 to @4.", ts, row.executor_name,
                target, s)
        else
            msg = S("@1: @2 set status to @3.", ts, row.executor_name, s)
        end

        local tooltip = S("No reason given.")
        if row.reason and row.reason ~= "" then
            tooltip = S("Reason: @1", row.reason)
        end
        if row.expires then
            msg = S("@1 (expires: @2)", msg, os.date("%Y-%m-%d", row.expires))
            tooltip = S("@1\nExpires: @2", tooltip, util.iso_date(row.expires))
        end
        if show_target_player then
            tooltip = S("@1\nClick to view player", tooltip)
        end

        local n = name .. i
        vbox[#vbox + 1] = gui.Stack{
            gui.Label{label = msg, w = 3, align_h = "left", expand = true},
            gui.ImageButton{
                name = n, w = 0, h = 0, expand = true,
                align_h = "fill", align_v = "fill", drawborder = false,

                -- Allow clicking on the main tab to take you to more info
                on_event = show_target_player and function(_, ctx)
                    ctx.form.tab = PLAYER
                    ctx.form.player = target
                    return true
                end or nil,
            },
            gui.Tooltip{gui_element_name = n, tooltip_text = tooltip},
        }
    end

    if show_more then
        vbox[#vbox + 1] = gui.Button{
            label = S("Load more"),
            on_event = function(_, ctx)
                ctx["fetch_" .. name] = ctx["fetch_" .. name] + 20
                return true
            end
        }
    end

    return gui.ScrollableVBox(vbox)
end

local function get_alts(player_id, show_entire_cluster)
    if show_entire_cluster then
        return data.get_player_cluster(player_id)
    end

    local alts = data.get_alts(player_id)

    local rows = {}
    for _, alt in ipairs(alts) do
        local alt_id = data.get_player_id(alt)
        if alt_id ~= player_id then
            local status = data.get_player_status(alt_id)
            rows[#rows + 1] = {
                player_name = alt,
                player_status_id = status and status.id
            }
        end
    end
    return rows
end

local search_field_names = {[PLAYER] = "player", [IP] = "ip", [ASN] = "asn"}
local function search_field(tab)
    return gui.HBox{
        gui.Field{
            label = S("@1:", mode_labels[tab]),
            name = search_field_names[tab], expand = true,
        },
        gui.Button{
            label = S("Search"), align_v = "end",
            on_event = function() return true end
        },
    }
end

local function chatcmd(cmd, param1, param_title)
    return function(_, ctx)
        if param1 then
            ctx.form[search_field_names[ctx.form.tab]] = param1
        end
        ctx.running_cmd = cmd
        ctx.running_cmd_param_title = param_title
        ctx.form.reason = nil
        return true
    end
end

local function cancel_chatcmd(_, ctx)
    ctx.running_cmd = nil
    ctx.running_cmd_param_title = nil
    ctx.form.reason = nil
    return true
end

local function run_chatcmd(player, ctx)
    local name = player:get_player_name()

    local cmd = minetest.registered_chatcommands[ctx.running_cmd]
    if cmd.privs and not minetest.check_player_privs(name, cmd.privs) then
        ctx.alert = S("Insufficient privileges")
    else
        local param = ctx.form[search_field_names[ctx.form.tab]]
        if ctx.form.reason and ctx.form.reason ~= "" then
            param = param .. " " .. ctx.form.reason
        end

        local ok, msg = cmd.func(name, param)
        if not ok then
            ctx.alert = msg or S("Invalid command usage!")
        elseif msg then
            minetest.chat_send_player(name, msg)
        end
    end
    return cancel_chatcmd(player, ctx)
end

local function asn_button(asn, asn_desc, truncate)
    local asn_status = data.get_asn_status(asn)
    return gui.Button{
        h = 0.6, name = "asn_info",
        label = asn_status_color(
            asn_status and asn_status.id,
            S("A@1 (@2)", asn, (truncate and #asn_desc > 30) and
            asn_desc:sub(1, 27) .. "..." or asn_desc)
        ),
        on_event = function(_, ctx)
            ctx.form.tab = ASN
            ctx.form.asn = "A" .. asn
            return true
        end,
    }
end

local verbana_gui_form = flow.make_gui(function(player, ctx)
    if not minetest.check_player_privs(player, verbana.privs.moderator) then
        return gui.Label{label = S("Permission denied!")}
    end

    -- Alerts
    if ctx.alert then
        return gui.VBox{
            gui.Label{label = ctx.alert},
            gui.Button{
                label = S("OK"),
                on_event = function()
                    ctx.alert = nil
                    return true
                end
            }
        }
    end

    -- Confirmation dialog when running chatcommands
    if ctx.running_cmd then
        return gui.VBox{
            gui.Label{label = S("Running /@1 @2", ctx.running_cmd,
                ctx.form[search_field_names[ctx.form.tab]])},
            ctx.running_cmd_param_title == "" and gui.Nil{} or gui.Field{
                name = "reason",
                label = ctx.running_cmd_param_title or S("Reason:")
            },
            gui.HBox{
                gui.Button{
                    w = 3, expand = true, label = S("Cancel"),
                    on_event = cancel_chatcmd
                },
                gui.Button{
                    w = 3, expand = true, label = S("Run"),
                    on_event = run_chatcmd
                }
            }
        }
    end

    local vbox = {
        min_w = 15, min_h = 11,

        gui.Tabheader{
            w = 3, h = 0.8, name = "tab", captions = mode_labels,
            transparent = true, draw_border = true,
        },
    }

    local tab = ctx.form.tab or HOME
    if tab == HOME then
        local verification = settings.universal_verification
        vbox[#vbox + 1] = gui.Label{
            label = verification and
                minetest.colorize("red",
                    S("Verification of new players is on")) or
                minetest.colorize("lightgreen",
                    S("Verification of new players is off"))
        }

        if minetest.check_player_privs(player, verbana.privs.admin) then
            vbox[#vbox + 1] = gui.Button{
                label = S("Toggle verification"),
                on_event = function()
                    settings.set_universal_verification(not verification)
                    return true
                end
            }
        end

        vbox[#vbox + 1] = gui.Label{label = S("Recent bans:")}
        ctx.fetch_recent_bans = ctx.fetch_recent_bans or 20
        vbox[#vbox + 1] = status_log(data.get_ban_log(ctx.fetch_recent_bans),
            "recent_bans", true, true)
    elseif tab == PLAYER then
        vbox[#vbox + 1] = search_field(tab)

        local player_id, player_name = data.get_player_id(ctx.form.player)
        if player_id then
            local ip = data.fumble_about_for_an_ip(player_name, player_id)
            local asn, asn_desc = lib_asn.lookup(lib_ip.ipstr_to_ipint(ip))

            local auth = minetest.get_auth_handler().get_auth(player_name) or {}
            local player_status = data.get_player_status(player_id)
            local player_status_id = player_status and player_status.id
            local ip_status = data.get_ip_status(ip)
            local main_acc_id, main_acc_name = data.get_master(player_id)

            local title = S("Ban record for @1", player_name)
            if main_acc_id then
                title = S("@1 (main account: @2)", title, main_acc_name)
            end

            table.insert_all(vbox, {
                gui.Label{label = title},

                gui.HBox{
                    gui.Label{label = S("Status: @1@2", get_status_name(player_status_id),
                        expired(player_status))},
                    gui.Spacer{},

                    -- Contextual action buttons
                    minetest.get_player_by_name(player_name) and gui.Button{
                        label = S("Kick"), h = 0.6,
                        on_event = chatcmd("kick"),
                    } or gui.Nil{},

                    main_acc_id and gui.Button{
                        label = S("Mark as not alt"), h = 0.6,
                        on_event = chatcmd("unmaster", nil, ""),
                    } or gui.Button{
                        label = S("Mark as alt"), h = 0.6,
                        on_event = chatcmd("master", nil, S("Main account name:")),
                    },

                    player_status_id == data.player_status.unverified.id and gui.Button{
                        label = S("Verify"), h = 0.6,
                        on_event = chatcmd("verify"),
                    } or gui.Button{
                        label = S("Unverify"), h = 0.6,
                        on_event = chatcmd("unverify"),
                    },
                    player_status_id == data.player_status.suspicious.id and gui.Button{
                        label = S("Unsuspect"), h = 0.6,
                        on_event = chatcmd("unsuspect"),
                    } or gui.Button{
                        label = S("Suspect"), h = 0.6,
                        on_event = chatcmd("suspect"),
                    },
                    player_status_id == data.player_status.banned.id and gui.Button{
                        label = S("Unban"), h = 0.6,
                        on_event = chatcmd("unban"),
                    } or gui.Button{
                        label = S("Ban"), h = 0.6,
                        on_event = chatcmd("ban"),
                    },
                },
                gui.Label{label = S("Last login: @1",
                    auth.last_login and util.iso_date(auth.last_login) or S("Unknown"))},

                gui.HBox{
                    gui.Label{label = S("ASN:")},
                    asn_button(asn, asn_desc, true),
                    gui.Tooltip{
                        gui_element_name = "asn_info",
                        tooltip_text = S("A@1 (@2)", asn, asn_desc)
                    },

                    gui.Spacer{},

                    gui.Label{label = S("IP:")},
                    gui.Button{
                        h = 0.6,
                        label = ip_status_color(ip_status and ip_status.id, ip),
                        on_event = function()
                            ctx.form.tab = IP
                            ctx.form.ip = ip
                            return true
                        end,
                    }
                },

                gui.Box{w = 0.05, h = 0.05, color = "darkgrey"},

                gui.HBox{
                    expand = true,
                    gui.VBox{
                        gui.Label{
                            label = S("Alternate accounts:")
                        },
                        gui.Checkbox{
                            name = "show_entire_cluster",
                            label = S("Show entire cluster"),
                        },
                        gui.Tooltip{
                            gui_element_name = "show_entire_cluster",
                            tooltip_text = S("Shows players who have " ..
                                "shared the same IP at any point in time."),
                        },
                        player_list(get_alts(player_id, ctx.form.show_entire_cluster))
                    },
                    gui.VBox{
                        expand = true,
                        gui.Label{
                            label = S("Status log:"),
                        },
                        status_log(data.get_player_status_log(player_id),
                            "pstatus")
                    },
                },
            })
        else
            vbox[#vbox + 1] = gui.Label{label = S("Unknown player")}
        end
    elseif tab == IP then
        vbox[#vbox + 1] = search_field(tab)

        local ip = ctx.form.ip
        if lib_ip.is_valid_ip(ip) then
            local ipint = lib_ip.ipstr_to_ipint(ip)
            local asn, asn_desc = lib_asn.lookup(ipint)
            local ip_status = data.get_ip_status(ipint)
            local ip_status_id = ip_status and ip_status.id

            table.insert_all(vbox, {
                gui.Label{
                    label = S("IP address @1", ip)
                },

                gui.HBox{
                    gui.Label{label = S("Status: @1@2",
                        get_ip_status_name(ip_status_id), expired(ip_status))},
                    gui.Spacer{},

                    -- Contextual action buttons

                    -- I can't get /ip_untrust to work so I've hidden the
                    -- "trust" button
                    ip_status_id == data.ip_status.trusted.id and gui.Button{
                        label = S("Untrust"), h = 0.6,
                        on_event = chatcmd("ip_untrust"),
                    } or gui.Nil{},
                    ip_status_id == data.ip_status.suspicious.id and gui.Button{
                        label = S("Unsuspect"), h = 0.6,
                        on_event = chatcmd("ip_unsuspect"),
                    } or gui.Button{
                        label = S("Suspect"), h = 0.6,
                        on_event = chatcmd("ip_suspect"),
                    },
                    ip_status_id == data.ip_status.blocked.id and gui.Button{
                        label = S("Unblock"), h = 0.6,
                        on_event = chatcmd("ip_unblock"),
                    } or gui.Button{
                        label = S("Block"), h = 0.6,
                        on_event = chatcmd("ip_block"),
                    },
                },

                gui.HBox{
                    gui.Label{label = S("ASN:")},
                    asn_button(asn, asn_desc, false),
                },

                gui.Box{w = 0.05, h = 0.05, color = "darkgrey"},

                gui.HBox{
                    expand = true,
                    gui.VBox{
                        gui.Label{
                            label = S("Accounts with this IP:")
                        },
                        player_list(data.get_ip_associations(ipint, 0))
                    },
                    gui.VBox{
                        expand = true,
                        gui.Label{
                            label = S("Status log:"),
                        },
                        status_log(data.get_ip_status_log(ipint),
                            "ip_status")
                    },
                },
            })
        else
            vbox[#vbox + 1] = gui.Label{label = S("Invalid IP")}
        end
    elseif tab == ASN then
        vbox[#vbox + 1] = search_field(tab)
        local asn = tonumber(((ctx.form.asn or ""):match("^A?(%d+)$"))) or 0
        local asn_description = lib_asn.get_description(asn)
        local asn_status = data.get_asn_status(asn)
        local asn_status_id = asn_status and asn_status.id
        local asn_str = "A" .. asn

        vbox[#vbox + 1] = gui.Label{
            label = S("A@1 (@2)", asn, asn_description)
        }

        vbox[#vbox + 1] = gui.HBox{
            gui.Label{label = S("Status: @1@2",
                get_asn_status_name(asn_status_id), expired(asn_status))},
            gui.Spacer{},

            -- Contextual action buttons
            asn_status_id == data.asn_status.suspicious.id and gui.Button{
                label = S("Unsuspect"), h = 0.6,
                on_event = chatcmd("asn_unsuspect", asn_str),
            } or gui.Button{
                label = S("Suspect"), h = 0.6,
                on_event = chatcmd("asn_suspect", asn_str),
            },

            asn_status_id == data.asn_status.blocked.id and gui.Button{
                label = S("Unblock"), h = 0.6,
                on_event = chatcmd("asn_unblock", asn_str),
            } or gui.Button{
                label = S("Block"), h = 0.6,
                on_event = chatcmd("asn_block", asn_str),
            },
        }

        vbox[#vbox + 1] = gui.Label{label = S("Player statistics:")}
        for _, row in ipairs(data.get_asn_stats(asn) or {}) do
            vbox[#vbox + 1] = gui.Label{label = S("@1: @2 player(s)",
                get_status_name(row.player_status_id), row.count)}
        end

        vbox[#vbox + 1] = gui.Box{w = 0.05, h = 0.05, color = "darkgrey"}

        vbox[#vbox + 1] = gui.Label{label = S("Status log:")}
        vbox[#vbox + 1] = status_log(data.get_asn_status_log(asn), "asn_status")
    elseif tab == REPORTS then
        ctx.report_days = ctx.report_days or 7
        vbox[#vbox + 1] = gui.Label{label = S("Reports from the past @1 days:",
            ctx.report_days)}
        local svbox = {name = "reports_svbox", height = 5, expand = true}
        local reports = data.get_reports(os.time() - 86400 * ctx.report_days)
        for i = #reports, 1, -1 do
            local row = reports[i]
            svbox[#svbox + 1] = gui.Label{label = S("@1: Report from @2",
                util.iso_date(row.timestamp), row.reporter)}
            svbox[#svbox + 1] = gui.Textarea{
                w = 5, min_h = 2, default = row.report:gsub("  ", "\n"),
            }

            -- Add a visible separator so that players can't try fake reports
            -- by other players
            svbox[#svbox + 1] = gui.Box{w = 0.05, h = 0.05, color = "darkgrey"}
        end

        svbox[#svbox + 1] = gui.Button{
            label = S("Load more"),
            on_event = function()
                ctx.report_days = ctx.report_days + 7
                return true
            end,
        }

        vbox[#vbox + 1] = gui.StyleType{selectors = {"label"}, props = {font = "bold"}}
        vbox[#vbox + 1] = gui.ScrollableVBox(svbox)
        vbox[#vbox + 1] = gui.StyleType{selectors = {"label"}, props = {font = ""}}
    end

    return gui.VBox(vbox)
end)

minetest.register_chatcommand("verbana_gui", {
    description = "Opens the verbana GUI",
    privs = {[verbana.privs.moderator] = true},
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return false end
        verbana_gui_form:show(player)
    end,
})

if minetest.global_exists("sway") then
    local pagename = "verbana_gui"
    sway.register_page(pagename .. ":gui", {
        title = S('Verbana'),
        is_in_nav = function(_, player, _)
            return verbana.privs.is_moderator(player:get_player_name())
        end,
        get = function(_, player, _)
            return sway.Form {
                verbana_gui_form:embed {
                    player = player,
                    name = pagename,
                }
            }
        end
    })
    local function on_priv_change(player_name, _, priv)
        if not sway.enabled then
            return
        end

        if priv ~= verbana.privs.moderator then
            return
        end

        local player = minetest.get_player_by_name(player_name)
        if not player then
            return
        end

        if sway.get_page(player) ~= pagename then
            return
        end

        sway.set_player_inventory_formspec(player)
    end
    minetest.register_on_priv_grant(on_priv_change)
    minetest.register_on_priv_revoke(on_priv_change)
end
