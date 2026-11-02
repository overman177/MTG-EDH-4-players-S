function swapPlayerWhite(player)
    swapPlayers(player, "White")
end

function swapPlayerRed(player)
    swapPlayers(player, "Red")
end

function swapPlayerOrange(player)
    swapPlayers(player, "Orange")
end

function swapPlayerYellow(player)
    swapPlayers(player, "Yellow")
end

function swapPlayerGreen(player)
    swapPlayers(player, "Green")
end

function swapPlayerBlue(player)
    swapPlayers(player, "Blue")
end

function swapPlayerPurple(player)
    swapPlayers(player, "Purple")
end

function swapPlayerPink(player)
    swapPlayers(player, "Pink")
end

function swapPlayers(a, bColor)
    b = Player[bColor]
    aColor = a.color
	
	if aColor == "Black" or bColor == "Black" then
        broadcastToColor("GM does not swap!", aColor)
        return
    end

    colorPlayer = Player[bColor]
    if colorPlayer.getHandCount() == 0 then
        broadcastToColor(bColor .. " seat is not available", aColor)
        return
    end

    aHandObjects = a.getHandObjects()
    bHandObjects = b.getHandObjects()

    aID = a.steam_id
    bID = b.steam_id

    a.changeColor("Grey")
    b.changeColor("Grey")

    for _,obj in ipairs(aHandObjects) do
        obj.deal(1, bColor)
    end

    local dealBtoA = function()
            for _,obj in ipairs(bHandObjects) do
                obj.deal(1, aColor)
            end    
        end

    Wait.time(dealBtoA, 0.2)

    local seatPlayersBack = function()
            for _,spectator in pairs(Player.getSpectators()) do
                if spectator.steam_id == aID then
                    spectator.changeColor(bColor)
                    break
                end
            end

            for _,spectator in pairs(Player.getSpectators()) do
                if spectator.steam_id == bID then
                    spectator.changeColor(aColor)
                    break
                end
            end
        end

    Wait.time(seatPlayersBack, 0.4)


end