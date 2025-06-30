
local skynet = require "skynet"
local s = require "service"
local runconfig = require "runconfig"
local mynode = skynet.getenv("node")

s.snode = nil --scene_node
s.sname = nil --scene_id

local function random_scene()
    --选择node
    local nodes = {}
    for i, v in pairs(runconfig.scene) do
        table.insert(nodes, i)
        if runconfig.scene[mynode] then
            table.insert(nodes, mynode)
        end
    end
    local idx = math.random( 1, #nodes)
    local scenenode = nodes[idx]
    --具体场景
    local scenelist = runconfig.scene[scenenode]
    local idx = math.random( 1, #scenelist)
    local sceneid = scenelist[idx]
    return scenenode, sceneid
end

s.client.enter = function(msg)
    print("call client.enter function")
    if s.sname then
        return {"enter",1,"已在场景"}
    end
    local snode, sid = random_scene()
    local sname = "scene"..sid
    local isok = s.call(snode, sname, "enter", s.id, mynode, skynet.self())
    if not isok then
        return {"enter",1,"进入失败"}
    end
    s.snode = snode
    s.sname = sname
    return nil
end

s.client.testFunc = function(msg)
    print("call client.test function")
    local isok = s.call(s.snode, s.sname, "testFunc")
    if not isok then
        return {"test",1,"失败"}
    end

    return nil
end

s.client.leave = function()
    --不在场景
    if not s.sname then
        return {"leave",1,"离开失败"}
    end
    s.call(s.snode, s.sname, "leave", s.id)
    s.snode = nil
    s.sname = nil
    return {"leave",0,"离开成功"}
end

s.client.bet = function(msg)
    local isok = s.call(s.snode, s.sname, "bet", s.id, mynode, skynet.self(),tonumber(msg[2]))
    if not isok then
        return {"bet",1,"bet失败"}
    end

    return {"bet",0,"bet成功"}
end

s.client.start_sendcard = function()
    local isok = s.call(s.snode, s.sname, "start_sendcard", s.id, mynode, skynet.self())
    if not isok then
        return {"start_sendcard",1,"start失败"}
    end

    return {"start_sendcard",0,"start成功"}
end

s.client.hit = function()
    local isok = s.call(s.snode, s.sname, "hit", s.id, mynode, skynet.self())
    if not isok then
        return {"hit",1,"hit失败"}
    end

    return {"hit",0,"hit成功"}
end

s.client.stand = function()
    local isok = s.call(s.snode, s.sname, "stand", s.id, mynode, skynet.self())
    if not isok then
        return {"stand",1,"stand失败"}
    end

    return {"stand",0,"stand成功"}
end