-- Report UI should prevent blank, invite-only, duplicate and rapid reports.
VERSION="test"
local sent=0
UI={setAttribute=function() end}
broadcastToColor=function() end
visibleCloseRules=function() end
JSON={encode=function() return "{}" end}
WebRequest={}
WebRequest.custom=function(_, _, _, _, _, cb)
    sent=sent+1
    WebRequest.lastCallback=cb
end
dofile("src/global/sections/38_bug-reports.lua")
local player={color="White",steam_id="test-steamid",steam_name="Tester"}
bugReportDraft={type="Bug report",title="short",description="no"}
submitBugReport(player)
assert(sent==0, "short report sent")
bugReportDraft={type="Bug report",title="https://discord.gg/4NvNKwMmCP",
    description="This is not a bug report; it is an invitation."}
submitBugReport(player)
assert(sent==0, "invite report sent")
bugReportDraft={type="Bug report",title="Deck shuffle triggers errors",
    description="Sometimes a shuffled deck produces an invalid object reference."}
submitBugReport(player)
assert(sent==1, "valid report not sent")
submitBugReport(player)
assert(sent==1, "duplicate in-flight report sent")
WebRequest.lastCallback({is_error=false,is_done=true,response_code=201})
submitBugReport(player)
assert(sent==1, "cooldown did not reject second report")
print("Report UI anti-spam: OK")
