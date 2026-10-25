-- Starts the addon: points the pieces at each other and loads the saved variables when the game has read them. The
-- slash command and the window come with the milestones after this one (docs/PLAN.md, "Milestones").

local ADDON, ns = ...

-- The addon's one global besides its saved variables, so a person can look inside from the game's /dump.
GuildGolem = ns

ns.version = ns.Client.addonVersion()

-- An error the game's functions raise is kept with the handlers' errors.
ns.Client.onError = function(where, message)
  ns.Store.recordError("game " .. where, message)
end

ns.Events.init()

ns.Events.on("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  local status, warning = ns.Store.init()
  if warning then print("|cffff8800Guild Golem:|r " .. warning) end
  ns.loaded = status
end, "main")
