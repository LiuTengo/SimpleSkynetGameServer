local skynet = require "skynet"
local s = require "service"

local players = {}
local deck = {}

local game_status = 0 -- 0——未开始 1——运行时 2——已停牌

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

local function reset_player_info(player)
    player.current_bet = 0
    player.card_count = 0
    player.handcards = {}
end

local function reset_player_coins(player)
    player.coins = player.coins + player.current_bet
    reset_player_info(player)
end

local function init_player_info(player)
    player.player_status = 0
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
        skynet.error("玩家人数不足 2 无法结算")
        return
    end

    local p1 = player_list[1]
    local p2 = player_list[2]

    local winner,loser = determine_winner(p1,p2)

    skynet.sleep(300)

    if winner and loser then
        local winmsg = {"result",0,winner.playerid} --result --0——has winner
        broadcast(winmsg)

        winner.coins = winner.coins + winner.current_bet + loser.current_bet
        reset_player_info(winner)
        reset_player_info(loser)
        
        --broadcast info
        local loser_info_msg = {"update_player_info",0,loser.playerid,loser.coins,loser.current_bet,"empty"}
        broadcast(loser_info_msg)
        local winner_info_msg = {"update_player_info",0,winner.playerid,winner.coins,winner.current_bet,"empty"}
        broadcast(winner_info_msg)
    else
        --no winner
        -- broadcast
        local game_result_msg = {"result",1} --result --1——no winner
        broadcast(game_result_msg)
    
        reset_player_coins(p1)
        reset_player_coins(p2)
    
        --broadcast info
        local p1_info_msg = {"update_player_info",0,p1.playerid,p1.coins,p1.current_bet,"empty"}
        broadcast(p1_info_msg)
        local p2_info_msg = {"update_player_info",0,p2.playerid,p2.coins,p2.current_bet,"empty"}
        broadcast(p2_info_msg)
    end
    game_status = 0
end

local function calculate_player_score(player,c)
    --calculate card value
    player.card_count = player.card_count + c.value
    if player.card_count > 21 then
        --player lose
        --calculate result
        player.player_status = 2
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

    local send_card_msg = {"send_card_to_player",0,player.playerid,c.suit,c.value}
    broadcast(send_card_msg)

    calculate_player_score(player,c)
    
    return true
end

local function reset_game()
    deck = {}
    game_status = 0
    --for _, p in pairs(players) do
    --    init_player_info(p)
    --end
end


--继续发牌
s.resp.hit = function(source, playerid, node, agent)
    local p = players[playerid]
    if p.player_status ~= 1 then
        local ret_msg = {"hit",1,"player status error"}
        s.send(node, agent, "send", ret_msg)
        return false
    end

    return send_card_to_player(p)
end

--停牌stand
s.resp.stand = function(source, playerid, node, agent)
    local p = players[playerid]
    if p.player_status ~= 1 then
        local ret_msg = {"stand",1,"player status error"}
        s.send(node, agent, "send", ret_msg)
        return false
    end

    p.player_status = 2
    local stand_msg = {"player_stand", 0 ,p.playerid}
    broadcast(stand_msg)

    local should_calculate_result = true
    for pid, player in pairs(players) do
        if player.player_status ~= 2 then
            should_calculate_result = false
        end
    end

    if should_calculate_result then
        --calculate result
        game_status = 2
        calculate_game_result()
    end
    return true
end

s.resp.restart_game = function(source, playerid, node, agent)
    for key, p in pairs(players) do
        init_player_info(p)
    
        local restart_msg = {"restart_player_info", 0 ,p.playerid, p.coins, p.current_bet, "empty"}
        broadcast(restart_msg)
    end
    
    local is_reset = true
    for key, player in pairs(players) do
        if player.player_status ~= 0 then
            is_reset = false
        end
    end
    if is_reset then
        game_status = 0
        local restart_msg = {"game_restart",0}
        broadcast(restart_msg)
        return true
    end
    return false
end

--下注
s.resp.bet = function(source, playerid, node, agent,bet)
    local p = players[playerid]
    if p.player_status ~= 0 then
        local ret_msg = {"bet",1,"player status error"}
        s.send(node, agent, "send", ret_msg)
        return false
    end

    if p then
        p.current_bet = p.current_bet + bet
        p.coins = p.coins - bet
        local ret_msg = {"bet",0,bet}
        s.send(node, agent, "send", ret_msg)

        local p_info_msg = {"update_player_info",0,p.playerid,p.coins,p.current_bet,"not empty"}
        broadcast(p_info_msg)

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
        player.player_status = 1
        if player.current_bet <= 0 then
            local ret_msg = {"start_sendcard",1,player.playerid,"未下注"}
            s.send(node, agent, "send", ret_msg)
            return false
        end
    end

    for i = 1, 2, 1 do
        for pid, player in pairs(players) do
            if not send_card_to_player(player) then
                return false
            end
        end
    end
    game_status = 1

    local start_msg = {"start_msg",0}
    broadcast(start_msg)

    return true
end

--进入
s.resp.enter = function(source, playerid, node, agent)
    if table_len(players) >= 2 then
        return false
    else
        local p =player(playerid,node,agent)



        players[playerid] = p
        reset_player_info(p)
        --local player_info_msg = {"update_player_info",p.playerid,p.coins,p.current_bet,{}}
        --broadcast(player_info_msg)

        --回应
        local ret_msg = {"enter",0,"进入成功"}
        s.send(node, agent, "send", ret_msg)

        --广播
        local entermsg = {"player_enter", 0 ,playerid}
        broadcast(entermsg)

        for key, playerInScene in pairs(players) do
            if playerInScene.playerid ~= playerid then
                local playermsg = {"player_in_scene", 0 ,playerInScene.playerid}
                broadcast(playermsg)
            end
        end
        
        --send card
        if table_len(players) == 2 then
            --player full send card
            deck = init_card_deck()
        end
    end
    return true
end

s.resp.get_player_info = function(source, playerid, node, agent)
    local p = players[playerid]
    
    if p then
        local p_info_msg = {"update_player_info",0,p.playerid,p.coins,p.current_bet,"empty"}
        broadcast(p_info_msg)
    else
        local p_error_info = {"update_player_info",1}
        broadcast(p_error_info)
    end

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

    reset_game()
    return true
end

s.init = function()
    skynet.error("init card 21 scene")
end

s.start(...)