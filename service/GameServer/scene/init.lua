local skynet = require "skynet"
local s = require "service"

local players = {}
local deck = {}

local function table_len(t)
    local n = 0
    for _, _ in pairs(t) do
        n = n + 1
    end
    return n
end

local function player(playerid,node,agent)
    local m = {
        playerid = playerid,
        node = node,
        agent = agent,
        coins = 500, --
        current_bet = 0,
        card_count = 0, -- 
        player_status = 0, --玩家状态： 0——准备 1——未停牌 2——已停牌
        handcards = {}
    }
    return m
end

local function card(cardsuit,cardvalue)
    local c = {
        suit = cardsuit,
        value = cardvalue
    }
    return c
end

local function broadcast(msg)
    for i, p in pairs(players) do
        s.send(p.node,p.agent,"send",msg)
    end
end


local function init_card_deck()
    local d = {}
    for suit = 1, 4, 1 do
        for val = 1,13,1 do
            table.insert(d,card(suit,val))
        end
    end
    return d
end

-- draw card from deck
local function draw_card(deck)
    if #deck == 0 then
        return nil -- 没牌了
    end
    local index = math.random(1, #deck)
    local card = deck[index]
    table.remove(deck, index)
    return card
end

local function calculate_player_coins(player)
    player.coins = player.coins + player.current_bet
    player.current_bet = 0
    player.card_count = 0
    player.handcards = {}
end

local function reset_player_info(player)
    player.current_bet = 0
    player.card_count = 0
    player.handcards = {}
end

local function determine_winner(p1, p2)
    local b1 = p1.card_count <= 21
    local b2 = p2.card_count <= 21

    if not b1 and not b2 then return nil end
    if b1 and not b2 then return p1,p2 end
    if not b1 and b2 then return p2,p1 end
    if p1.card_count > p2.card_count then return p1,p2 end
    if p2.card_count > p1.card_count then return p2,p1 end
    return nil
end

local function calculate_game_result()
    local player_list = {}
    for _, p in pairs(players) do
        table.insert(player_list, p)
    end

    if #player_list ~= 2 then
        skynet.error("玩家人数不足 2，无法结算")
        return
    end

    local p1 = player_list[1]
    local p2 = player_list[2]

    local winner,loser = determine_winner(p1,p2)
    if winner and loser then
        local entermsg = {"result",1,winner.playerid} --result --1——has winner
        broadcast(entermsg)

        winner.coins = loser.coins + winner.current_bet + loser.current_bet
        winner.current_bet = 0
        winner.card_count = 0
        winner.handcards = {}
        loser.card_count = 0
        loser.current_bet = 0
        loser.handcards = {}

        --broadcast info
        local entermsg = {"update_player_info",loser.playerid,loser.coins,loser.handcards}
        broadcast(entermsg)
        local entermsg = {"update_player_info",winner.playerid,winner.coins,winner.handcards}
        broadcast(entermsg)
    else
        --no winner
        -- broadcast
        local entermsg = {"result",0} --result --0——no winner
        broadcast(entermsg)
    
        calculate_player_coins(p1)
        calculate_player_coins(p2)
    
        --broadcast info
        local entermsg = {"update_player_info",p1.playerid,p1.coins,p1.handcards}
        broadcast(entermsg)
        local entermsg = {"update_player_info",p2.playerid,p2.coins,p2.handcards}
        broadcast(entermsg)
    end
end

local function calculate_player_score(player,c)
    --calculate card value
    player.card_count = player.card_count + c.value
    if player.card_count > 21 then
        --player lose
        --calculate result
        calculate_game_result()
    end
    return true
end


local function send_card_to_player(player)
    local c = draw_card(deck)
    if not c then
        local card_msg = {"card",1,"牌库为空"}
        s.send(player.node, player.agent, "send", card_msg)
        return false
    end

    table.insert(player.handcards,c)
    local card_msg = {"card",0,c.suit,c.value}
    s.send(player.node, player.agent, "send", card_msg)
    calculate_player_score(player,c)
    
    return true
end

--继续发牌
s.resp.hit = function(source, playerid, node, agent)
    return send_card_to_player(players[playerid])
end

--stand
s.resp.stand = function(source, playerid, node, agent)
    players[playerid].player_status = 2

    local should_calculate_result = true
    for pid, player in pairs(players) do
        if player.player_status ~= 2 then
            should_calculate_result = false
        end
    end

    if should_calculate_result then
        --calculate result
        calculate_game_result()
    end
    return true
end

s.resp.bet = function(source, playerid, node, agent,bet)
    local p = players[playerid]
    if p then
        p.current_bet = p.current_bet + bet
        local ret_msg = {"bet",0,"下注成功"}
        s.send(node, agent, "send", ret_msg)
        return true
    else
        local ret_msg = {"bet",1,"下注失败，玩家为空"}
        s.send(node, agent, "send", ret_msg)
        return false
    end
end

-- start game
s.resp.start_sendcard = function(source, node, agent)
    if table_len(players) ~= 2 then
        local ret_msg = {"start_sendcard",1,"人数未满"}
        s.send(node, agent, "send", ret_msg)
        return false
    end

    for pid, player in pairs(players) do
        if player.current_bet <= 0 then
            local ret_msg = {"start_sendcard",1,player.playerid,"未下注"}
            s.send(node, agent, "send", ret_msg)
            return false
        end
    end

    for i = 1, 2, 1 do
        for pid, player in pairs(players) do
            send_card_to_player(player)
        end
    end
    local ret_msg = {"start_sendcard",0,"开始游戏"}
    s.send(node, agent, "send", ret_msg)
    return true
end

--进入
s.resp.enter = function(source, playerid, node, agent)
    if table_len(players) >= 2 then
        return false
    else
        players[playerid]=player(playerid,node,agent)
        reset_player_info(players[playerid])
        --广播
        local entermsg = {"enter", playerid}
        broadcast(entermsg)
        --回应
        local ret_msg = {"enter",0,"进入成功"}
        s.send(node, agent, "send", ret_msg)

        --send card
        if table_len(players) == 2 then
            --player full send card
            deck = init_card_deck()
        end
    end
    return true
end

s.resp.testFunc = function()
    print("test function......")
    print("players count = " .. tostring(table_len(players)))
    for k,player in pairs(players) do
        print("player bet = " .. tostring((player.current_bet)))
        print("player handcard count = " .. tostring(#(player.handcards)))
        for i = 1,#player.handcards,1 do
            print(player.handcards[i].suit .." ".. player.handcards[i].value)
        end
    end 
end

--退出
s.resp.leave = function(source, playerid)
    if not players[playerid] then
        return false
    end
    players[playerid] = nil

    local leavemsg = {"leave", playerid}
    broadcast(leavemsg)
    return true
end

s.init = function()
    skynet.error("init card 21 scene")
end

s.start(...)