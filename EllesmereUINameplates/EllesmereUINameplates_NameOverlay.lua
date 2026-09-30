if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local addon, ns = ...

if not ns then return end

-- Name z-order (name slot Strata).
--
-- The name slot's Strata setting places the name FontString anywhere in the plate's z-stack so
-- it can sit ABOVE or BELOW the aura buttons (and other plate elements). The aura buttons are
-- Blizzard restricted/forbidden regions, but they are children of the Ellesmere plate and render
-- at their own frame strata/level WITHIN it -- they are NOT a separate always-on-top overlay
-- (live-verified: a MEDIUM name at level ~900 draws above the ~800 aura tier). So placing the
-- name's host frame at the chosen strata orders it against them across the whole range:
--   BACKGROUND / LOW -> name behind the auras
--   MEDIUM           -> the shared text tier (name level ~900 > the ~800 aura tier)
--   HIGH / DIALOG    -> name in front of the auras
--
-- ns.SlotTextHost(plate, slot, strata) sets that host's strata and returns it; RefreshNamePosition
-- already parents the name there. This module just re-asserts it from the settings/scale passes so
-- a strata change on a live plate takes effect immediately. There is deliberately NO UIParent lift:
-- reparenting the name out to UIParent put it in a separate render root that draws above the whole
-- plate at EVERY strata, which defeated BACKGROUND/LOW. Taint-safe: only the insecure, addon-owned
-- host frame's strata is set; no protected function or secure attribute is touched.

function ns.RefreshNameOverlay(plate)
    local name = plate and plate.name
    if not name then return end
    local prof = ns.db and ns.db.profile
    local nameSlot = ns.FindNameSlot and ns.FindNameSlot()
    if not (prof and nameSlot and ns.SlotTextHost) then return end
    local strata = prof[nameSlot .. "Strata"] or "MEDIUM"
    local host = ns.SlotTextHost(plate, nameSlot, strata)   -- sets the host's strata, returns it
    if not host then return end
    if name:GetParent() ~= host then name:SetParent(host) end
    local nameRaid = plate.nameRaidFrame
    if nameRaid and plate._nameRaidMarkerShown and nameRaid:GetParent() ~= host then
        nameRaid:SetParent(host)
        nameRaid:SetFrameStrata(strata)
        nameRaid:SetFrameLevel(901)
    end
end
