-- Mocked Lua 5.2: bounded, explicit, deduplicated remote card lookups.
local objects, requests, messages, watches = {}, {}, {}, {}
local function card(guid,name)
    local obj={type="Card",is_face_down=false}
    obj.getName=function() return name end
    objects[guid]=obj
    return obj
end
function getObjectFromGUID(guid) return objects[guid] end
function mtgCardMetadata(params)
    local obj=objects[params.guid]
    if not obj then return nil end
    return {guid=params.guid, name=obj.getName():match("^[^\n]+")}
end
function printToColor(message,color)
    messages[#messages+1]={message=message,color=color}
end
Wait={time=function(fn) watches[#watches+1]=fn end}
JSON={decode=function(raw)
    if raw=="mtga" then
        return {cards={
            {name="Lightning Bolt",type_line="Instant",rules_text="Rebalanced",
                is_rebalanced=true,is_primary=true},
            {name="Lightning Bolt",type_line="Instant",rules_text="Deal 3 damage",
                is_primary=true,is_rebalanced=false,arena_id=1234}
        }}
    elseif raw=="scryfall" then
        return {name="Swords to Plowshares",type_line="Instant",
            oracle_text="Exile target creature.",id="test-scryfall-id"}
    end
    return {}
end}
WebRequest={custom=function(url,method,download,body,headers,callback)
    assert(method=="GET" and download==true and headers["User-Agent"])
    requests[#requests+1]={url=url,callback=callback}
end}
card("111111","Lightning Bolt\nInstant 1CMC")
card("222222","Lightning Bolt\nInstant 1CMC")
card("333333","Swords to Plowshares\nInstant 1CMC")
card("444444","Unknown\nCreature 1CMC")
local hidden=card("555555","A secret");hidden.is_face_down=true

dofile("src/global/sections/00b_card-catalog.lua")
local first=mtgCardCatalogRequest({guid="111111", color="White"})
local second=mtgCardCatalogRequest({guid="222222", color="Blue"})
assert(first.status=="pending" and second.status=="pending")
assert(#requests==1,"same name must coalesce into one MTGA request")
assert(mtgCardCatalogGet({guid="111111"}).status=="pending")
requests[1].callback({response_code=200,is_error=false,text="mtga"})
local ready=mtgCardCatalogGet({guid="111111"})
assert(ready.status=="ready" and ready.remote.source=="mtga")
assert(ready.remote.rulesText=="Deal 3 damage","prefer normal printing")
assert(#messages>=2,"notify both waiting seats")

local pending=mtgCardCatalogRequest({guid="333333",color="White"})
assert(pending.status=="pending" and #requests==2)
requests[2].callback({response_code=404,is_error=false,text=""})
assert(#requests==3 and requests[3].url:find("scryfall.com",1,true))
requests[3].callback({response_code=200,is_error=false,text="scryfall"})
local fallback=mtgCardCatalogGet({guid="333333"})
assert(fallback.status=="ready" and fallback.remote.source=="scryfall")
assert(#requests==3,"fallback is cached")
assert(mtgCardCatalogRequest({guid="333333"}).status=="ready")
assert(#requests==3,"cache hit does not fetch again")

local missing=mtgCardCatalogRequest({guid="444444"})
assert(missing.status=="pending")
requests[4].callback({response_code=404,is_error=false,text=""})
requests[5].callback({response_code=404,is_error=false,text=""})
assert(mtgCardCatalogGet({guid="444444"}).status=="miss")
assert(mtgCardCatalogRequest({guid="555555"}).status=="invalid",
    "hidden cards must not be looked up")
print("MTGA/Scryfall on-demand cache/fallback/face-down tests passed.")
