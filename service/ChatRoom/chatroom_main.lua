local skynet = require "skynet"
local socket = require "skynet.socket"

local clients = {}
local host = "0.0.0.0"

local function connect(socket_id,IPAddress)

	print(socket_id .. ' connect address '.. IPAddress)

	socket.start(socket_id)
	clients[socket_id] = {}
	local dont_close = true

	while dont_close do
		local readdata = socket.read(socket_id)
		if readdata ~= nil and readdata then

			if string.lower(tostring(readdata)) == 'exit' then
				dont_close = false
			end

			print(socket_id .. " recieve : " .. tostring(readdata))
			for i,_ in pairs(clients) do
				socket.write(i,tostring(readdata))
			end
        else
            skynet.error("ReadData is nil")
            dont_close = true;
            break
        end
	end
    print(socket_id .. 'close')
	socket.close(socket_id)
	clients[socket_id] = nil
	
end

skynet.start(
	function()
		local socketID = socket.listen(host,8888)
		socket.start(socketID,connect)
	end
)
