-- Point each External (Tuning) chain at whichever device currently matches its
-- pattern.
--
-- The chains are per CLASS, not per device: one for Bluetooth, one for wired
-- and USB. That is what makes a newly paired device work with nothing to run
-- and nothing watching -- it matches an existing chain the moment it appears.
-- Per-device chains were tried first and cannot do that: PipeWire reads filter
-- chains only at startup, pw-cli modules die with the client, pipewire-pulse
-- has no module-filter-chain, and WirePlumber's Lua sandbox blocks os.execute,
-- so a new device's chain could not exist without regenerating the config and
-- restarting PipeWire.
--
-- GNOME selects the hardware device for Bluetooth and USB. The wired
-- chain itself is the entry for the onboard jack. Each chain starts on
-- raw hardware until this script can resolve the selected output.

log = Log.open_topic ("s-external-target")

INTERNAL = "HiFi__Speaker__sink"
local HEADPHONES = "alsa_output.pci-0000_04_00.6.HiFi__Headphones__sink"

metadata_om = ObjectManager {
  Interest { type = "metadata", Constraint { "metadata.name", "=", "default" } }
}

sinks_om = ObjectManager {
  Interest { type = "node", Constraint { "media.class", "=", "Audio/Sink" } }
}

-- Matched on node.name rather than on speaker-dsp.match being present: an
-- ObjectManager Interest on a custom dotted key matched nothing here, while the
-- property itself is plainly readable from the node once matched this way.
chains_om = ObjectManager {
  Interest { type = "node",
    Constraint { "node.name", "matches", "effect_output.tuned-*" } }
}

-- A candidate is any sink that is not the built-in speaker and is not one of
-- our own chains.
--
-- Excluding every node carrying node.link-group was wrong and cost a Bluetooth
-- device: when earbuds are in headset mode WirePlumber builds a loopback pair
-- for the microphone, so the sink itself carries node.link-group =
-- "loopback-NNNN-NN" and was rejected -- the Bluetooth chain then fell all the
-- way back to the built-in speaker. Only OUR link-groups may be excluded, and
-- those are named after the chain.
local function candidates (pattern)
  local out = {}
  for node in sinks_om:iterate () do
    local props = node.properties
    local name = props["node.name"]
    local group = props["node.link-group"]
    if name ~= nil
        and (group == nil or not group:match ("^tuned%-"))
        and not name:match ("^effect_")
        and not name:match (INTERNAL)
        and name:match (pattern) then
      table.insert (out, { name = name,
                           prio = tonumber (props["priority.session"]) or 0 })
    end
  end
  table.sort (out, function (a, b) return a.prio > b.prio end)
  return out
end

local function default_sink ()
  local md = metadata_om:lookup ()
  if md == nil then return nil end
  local def = md:find (0, "default.audio.sink")
  if def == nil then return nil end
  local json = Json.Raw (def)
  if not json:is_object () then return nil end
  local parsed = json:parse ()
  return parsed and parsed["name"] or nil
end

local function apply ()
  local md = metadata_om:lookup ()
  if md == nil then return end

  local selected = default_sink ()
  for chain in chains_om:iterate () do
    local props = chain.properties
    local pattern = props["speaker-dsp.match"]
    local id = chain["bound-id"]
    if pattern ~= nil and id ~= nil then
      local found = candidates (pattern)
      local want = nil
      if selected == "effect_input.tuned-wired"
          and props["node.name"] == "effect_output.tuned-wired" then
        -- GNOME's jack entry selects a card profile. Wait for its sink even
        -- when a higher-priority USB device already matches this chain.
        want = HEADPHONES
      elseif #found > 0 then
        want = found[1].name
        for _, device in ipairs (found) do
          if device.name == selected then
            want = selected
            break
          end
        end
      else
        -- Park an unused class on raw hardware so it cannot feed another
        -- tuned sink. A missing explicit target waits for hardware.
        local any = candidates ("^")
        if #any > 0 then
          want = any[1].name
        else
          for node in sinks_om:iterate () do
            local n = node.properties["node.name"]
            if n ~= nil and n:match (INTERNAL) then want = n end
          end
        end
      end
      if want ~= nil and md:find (id, "target.object") ~= want then
        md:set (id, "target.object", "Spa:String", want)
        log:info (tostring (props["node.name"]) .. " -> " .. want)
      end
    end
  end
end

-- Move any stream sent to an external device into that device's chain.
--
-- This is what lets GNOME list the real device names while everything is still
-- processed: the user picks "OPPO Enco Buds", and the stream is redirected into
-- effect_input.tuned-bluetooth, whose own output goes to the buds.
--
-- WirePlumber's smart filters exist to do exactly this and do not work on
-- 0.5.13 -- they splice a chain in front of a device and then do not process
-- it, measured four different ways. Redirecting the stream instead does work,
-- and WirePlumber does not fight it: a stream moved this way stays moved.
--
-- The chain's OWN output stream must never be redirected, or it would feed
-- itself; those carry node.link-group and an effect_ name, and are skipped.
streams_om = ObjectManager {
  Interest { type = "node",
    Constraint { "media.class", "=", "Stream/Output/Audio" } }
}

local function chain_for (device)
  for chain in chains_om:iterate () do
    local pattern = chain.properties["speaker-dsp.match"]
    if pattern ~= nil and device:match (pattern) then
      -- chains_om holds the effect_output node; its sink is the matching input.
      local name = chain.properties["node.name"]
      return (name:gsub ("^effect_output%.", "effect_input."))
    end
  end
  return nil
end

-- Redirect app streams into the chain for the currently selected device, and
-- just as importantly, LET THEM GO again when the selection changes.
--
-- Writing target.object pins a stream: an explicit target beats the default
-- sink. So a stream redirected into a chain stays there when the listener
-- picks a different output in GNOME -- selecting the built-in speaker while a
-- song was playing left the audio coming out of the USB speaker, with GNOME
-- showing the built-in one as selected. Reported from real use; the earlier
-- test missed it because a stream started AFTER the switch follows the default
-- normally and only an already-playing one is pinned.
--
-- So every stream is repointed on every pass: to the chain when an external
-- device is selected, and to the selection itself when it is not.
local function redirect ()
  local md = metadata_om:lookup ()
  if md == nil then return end
  local def = default_sink ()
  if def == nil then return end

  local want = nil
  if not def:match ("^effect_") and not def:match (INTERNAL) then
    want = chain_for (def)
  end

  for stream in streams_om:iterate () do
    local props = stream.properties
    local name = props["node.name"] or ""
    local group = props["node.link-group"]
    -- Never touch a chain's own output stream: it would feed itself.
    if not name:match ("^effect_output%.")
        and (group == nil or not group:match ("^tuned%-")) then
      local id = stream["bound-id"]
      if id ~= nil then
        local cur = md:find (id, "target.object")
        if want ~= nil then
          if cur ~= want then
            md:set (id, "target.object", "Spa:String", want)
            log:info ("stream " .. name .. " -> " .. want)
          end
        elseif cur ~= nil and cur ~= def and cur:match ("^effect_input%.tuned%-") then
          -- We pinned this one; hand it back to the current selection.
          md:set (id, "target.object", "Spa:String", def)
          log:info ("stream " .. name .. " released -> " .. def)
        end
      end
    end
  end
end

-- A selection can move between devices behind the same chain. Point its
-- output first, then move any app streams that need the new chain.
local function refresh ()
  apply ()
  redirect ()
end

metadata_om:connect ("object-added", function (_, md)
  md:connect ("changed", function (_, subject, key)
    if key == "default.audio.sink" then refresh () end
  end)
end)
-- These notifications see the complete manager inventory, including nodes
-- which appeared after the default was restored during startup.
metadata_om:connect ("objects-changed", refresh)
chains_om:connect ("objects-changed", refresh)
sinks_om:connect ("objects-changed", refresh)
streams_om:connect ("objects-changed", redirect)

metadata_om:activate ()
sinks_om:activate ()
streams_om:activate ()
chains_om:activate ()
