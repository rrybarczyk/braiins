#!/usr/bin/lua

-- Copyright (C) 2020  Braiins Systems s.r.o.
--
-- This file is part of Braiins Open-Source Initiative (BOSI).
--
-- BOSI is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- Please, keep in mind that we may also license BOSI or any part thereof
-- under a proprietary license. For more information on the terms and conditions
-- of such proprietary license or if you have any other questions, please
-- contact us at opensource@braiins.com.

-- This is implementation of a simple ip address reporting protocol for Antminer S9 and such.
-- Original listening application to work with can be found here:
--   https://support.bitmain.com/hc/en-us/articles/360009263654-Where-and-how-to-use-IP-Reporter


-- port that app is supposed to listen on
local REPORTER_PORT = 14235

-- port we bind to
local MY_PORT = 14236

-- how long to wait for reporter app reply
local REPLY_TIMEOUT = 3

local socket = require "socket"
local io = require "io"
local uci = require "uci"
local nixio = require "nixio"


function get_net_info()
	-- divine our ip and ethernet addresses

	local mac, ip
	local ifaces = nixio.getifaddrs()
	for k, v in pairs(ifaces) do
		if v["name"] == "br-lan" then
			if v["family"] == "packet" then
				mac = v["addr"]
			elseif v["family"] == "inet" then
				ip = v["addr"]
			end
		end
	end
	-- NOTE the hostname can also be obtained from uci system.@system[0].hostname
	local hostname = nixio.uname()["nodename"]
	return mac, ip, hostname
end


local function pong(message_format)
	-- run through ip report dance

	nixio.syslog("debug", "Broadcasting IP")
	local sock = assert(socket.udp())
	-- original ip reporter app seems to be fine with handshake coming from different port,
	-- we bind to same port mostly to use as poor man's exclusive lock
	if not sock:setsockname("*", MY_PORT) then
		-- already running
		return
	end
	assert(sock:settimeout(REPLY_TIMEOUT))
	assert(sock:setoption("broadcast", true))

	local my_mac, my_ip, my_host = get_net_info()
	local message = message_format:gsub("${MAC}", my_mac)
	local message = message:gsub("${IP}", my_ip)
	local message = message:gsub("${HOSTNAME}", my_host)

	-- first we broadcast message with our info
	assert(sock:sendto(message , "255.255.255.255", REPORTER_PORT))

	-- reporter app should respond by sending back mac
	local data, remote_ip, remote_port = sock:receivefrom()
	if data == my_mac then
		-- which we then confirm
		assert(sock:sendto("OK\0", remote_ip, remote_port))
		-- NOTE
		-- unlike original implementation, we do not broadcast confirmation
		-- also know that original implementation adds some more bytes which are probably garbage
		-- just in case, captured data was: 'OK\x00\x00send_a'
		nixio.syslog("info", "Confirmed IP report to "..remote_ip)
	end
end


nixio.openlog("ipreporter")
local cursor = uci.cursor()

if (cursor.get("bos", "ip_report", "enable") or "1") == "1" then
	-- "${IP},${MAC}" is default since that is what stock IP reporter tool expects
	local message_format = cursor.get("bos", "ip_report", "format") or "${IP},${MAC}"
	pong(message_format)
end
