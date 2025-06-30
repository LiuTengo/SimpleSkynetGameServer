local skynet = require "skynet"
local socket = require "skynet.socket"

local clients = {}
local host = '192.168.1.22'

function connect(socket_id,IPAddress)
	print(socket_id .. ' connect address '.. IPAddress)
	socket.start(socket_id)
	clients[socket_id] = {}
	local close = true

	while close do
		local readdata = socket.read(socket_id)
		if readdata ~= nil then

			if string.lower(readdata) == 'exit' then
				close = false
				break
			end

			print(socket_id .. " recieve : " .. readdata)
			for i,_ in pairs(clients) do
				socket.write(i,readdata)
			end

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
