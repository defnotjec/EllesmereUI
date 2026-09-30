if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local addon, ns = ...

if not ns then return end

-- Name In Front of Auras.
--
-- Setting a name slot's strata to HIGH lifts the name text out of the plate's MEDIUM
-- render tree into a small per-plate container under UIParent at HIGH strata, so the
-- name draws ABOVE the in-plate aura buttons. This is the ONLY thing that works:
-- nameplate aura buttons are Blizzard's restricted/forbidden regions, rendered in a
-- protected compositing pass that sits above ordinary addon regions no matter what
-- strata/level an in-plate name is given (a MEDIUM/level-900 name still loses). Leaving
-- the plate's render tree -- exactly what the cast overlay does (EllesmereUINameplates_
-- CastOverlay.lua) -- is the escape hatch.
--
-- Taint-safety: only insecure, addon-owned frames are touched (a new UIParent child and
-- plate.name, an Ellesmere-created FontString). No protected function is called and no
-- secure frame's protected attributes are written, so nothing here can taint gameplay --
-- identical guarantees to the cast overlay. The name is a RESTRICTED region (its geometry
-- can't be measured by addon code), so we NEVER call SetPoint/GetLeft on it while lifted:
-- it keeps the cross-parent anchor RefreshNamePosition already set to plate.health, which
-- the engine resolves internally, so the lifted name tracks the plate for free.
--
-- Scale: the container uses SetIgnoreParentScale(true) pinned to the plate's effective
-- scale, so the name renders at exactly its on-plate size (re-synced from ApplyScale).
--
-- Visibility: the container lives under UIParent, not the plate, so it is slaved to the
-- plate's shown state (OnShow/OnHide hooks) -- a lifted name never lingers after the plate
-- is released/pooled.
--
-- Cost: one frame per plate (lazy, only when a name is actually lifted), one SetParent per
-- lift/unlift, and a scale compare per ApplyScale. Nothing at all while every name is MEDIUM.

local LIFT_STRATA = "HIGH"

local function GetNameLift(plate)
    local lift = plate._nameLift
    if not lift then
        lift = CreateFrame("Frame", nil, UIParent)
        lift:SetFrameStrata(LIFT_STRATA)
        lift:SetIgnoreParentScale(true)
        lift:SetSize(1, 1)
        lift:EnableMouse(false)
        if lift.EnableMouseMotion then lift:EnableMouseMotion(false) end
        plate._nameLift = lift
        -- Slave the container to the plate: a UIParent child would otherwise keep
        -- showing a released plate's name.
        plate:HookScript("OnHide", function() lift:Hide() end)
        plate:HookScript("OnShow", function() if plate._nameLifted then lift:Show() end end)
    end
    return lift
end

-- The name is lifted whenever its assigned text slot's strata is raised above the shared
-- MEDIUM text tier. Returns that strata ("HIGH" / "DIALOG" / ...) so the lift container can
-- match it, or nil for MEDIUM (no lift).
local function LiftStrata(plate)
    local prof = ns.db and ns.db.profile
    if not prof then return nil end
    local nameSlot = ns.FindNameSlot and ns.FindNameSlot()
    if not nameSlot then return nil end
    local s = prof[nameSlot .. "Strata"] or "MEDIUM"
    if s == "MEDIUM" then return nil end
    return s
end

-- Reparent the name (and its raid marker) back into the in-plate host. Mirrors the
-- host resolution RefreshNamePosition uses, so an unlift from any call path is correct.
local function Unlift(plate)
    plate._nameLifted = nil
    plate._nameLiftScale = nil
    if plate._nameLift then plate._nameLift:Hide() end
    local nameSlot = ns.FindNameSlot and ns.FindNameSlot()
    local host = (nameSlot and ns.SlotTextHost) and ns.SlotTextHost(plate, nameSlot, "MEDIUM")
        or plate.healthTextFrame
    if not host then return end
    if plate.name and plate.name:GetParent() ~= host then plate.name:SetParent(host) end
    local nameRaid = plate.nameRaidFrame
    if nameRaid then
        nameRaid:SetParent(host)
        nameRaid:SetFrameStrata("MEDIUM")
        nameRaid:SetFrameLevel(901)
    end
end

-- Idempotent: applies the current name-strata choice to one plate. Called at the tail of
-- RefreshNamePosition (settings/target/name changes -- which always reparents the name to
-- its in-plate host first, so this only has to lift) and RefreshNamePosition-free scale
-- passes via ApplyScale (scale re-sync).
function ns.RefreshNameOverlay(plate)
    local name = plate and plate.name
    if not name then return end
    local strata = LiftStrata(plate)
    if strata then
        local lift = GetNameLift(plate)
        lift:SetFrameStrata(strata)   -- honor the chosen strata (HIGH / DIALOG / ...)
        lift:Show()
        local nameRaid = plate.nameRaidFrame
        if name:GetParent() ~= lift then
            -- The name is a restricted region; SetParent is not a measurement so it should
            -- be allowed, but guard it so a block can never break RefreshNamePosition -- a
            -- failure just leaves the name in-plate (visible as MEDIUM in the frame dump).
            local ok = pcall(name.SetParent, name, lift)
            plate._nameLiftBlocked = (not ok) or nil
            if ok then
                if nameRaid and plate._nameRaidMarkerShown then
                    pcall(nameRaid.SetParent, nameRaid, lift)
                    nameRaid:SetFrameLevel(901)
                end
                plate._nameLifted = true
            end
        end
        if nameRaid and plate._nameRaidMarkerShown and nameRaid:GetParent() == lift then
            nameRaid:SetFrameStrata(strata)
        end
        local s = plate:GetEffectiveScale()
        if plate._nameLiftScale ~= s then
            plate._nameLiftScale = s
            lift:SetScale(s)
        end
    elseif plate._nameLifted then
        Unlift(plate)
    end
end
