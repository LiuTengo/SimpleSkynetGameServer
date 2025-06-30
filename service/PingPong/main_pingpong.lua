local skynet = require "skynet"

skynet.start(function()
    skynet.error("PingPong Start")
    local ping1 = skynet.newservice("pingpong")
    local pong2 = skynet.newservice("pingpong")

    skynet.send(ping1,"lua","start",pong2)
    skynet.exit()
end)