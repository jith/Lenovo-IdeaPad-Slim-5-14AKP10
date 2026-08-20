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
-- The cost is the name: GNOME shows the class, not "OPPO Enco Buds", because a
-- node cannot be renamed at runtime.
--
-- WHY THIS SCRIPT IS NOT OPTIONAL. A chain whose target does not resolve does
-- not go quiet -- PipeWire routes its output to the default sink, which is the
-- other tuned sink, and the stream is processed twice by two chains tuned
-- differently. Verified 20 Aug 2026. node.autoconnect = false prevents that but
-- also prevents this script's retarget, so the guard has to be that this runs.

log = Log.open_topic ("s-external-target")

INTERNAL = "HiFi__Speaker__sink"

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

local function apply ()
  local md = metadata_om:lookup ()
  if md == nil then return end

  for chain in chains_om:iterate () do
    local props = chain.properties
    local pattern = props["speaker-dsp.match"]
    local id = chain["bound-id"]
    if pattern ~= nil and id ~= nil then
      local found = candidates (pattern)
      local want = nil
      if #found > 0 then
        want = found[1].name
      else
        -- Nothing of this class is connected. The chain still exists -- these
        -- are per class, so "Bluetooth (Tuning)" is listed whether or not any
        -- Bluetooth device is -- and leaving it unpointed is NOT harmless:
        -- PipeWire routes an unresolved chain to the default sink, which is the
        -- other tuned sink, and the stream is then processed twice by two
        -- chains. Measured 20 Aug 2026 with the earbuds off.
        --
        -- So park it on a real device instead: any other external one, else the
        -- built-in speaker. Selecting a class with nothing connected then plays
        -- somewhere audible and is processed exactly once.
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

local function redirect ()
  local md = metadata_om:lookup ()
  if md == nil then return end
  for stream in streams_om:iterate () do
    local props = stream.properties
    local name = props["node.name"] or ""
    if not name:match ("^effect_output%.")
        and props["node.link-group"] == nil then
      local id = stream["bound-id"]
      -- A stream that simply follows the default output carries no
      -- target.object at all, which is the ordinary case for every app -- the
      -- first version only looked at explicit targets and so redirected
      -- nothing. Fall back to whatever the default sink currently is.
      local want_dev = nil
      if id ~= nil then
        want_dev = md:find (id, "target.object")
        if want_dev == nil then
          local def = md:find (0, "default.audio.sink")
          if def ~= nil then
            local json = Json.Raw (def)
            if json:is_object () then
              local parsed = json:parse ()
              want_dev = parsed and parsed["name"] or nil
            end
          end
        end
      end
      if id ~= nil and want_dev ~= nil
          and not want_dev:match ("^effect_")
          and not want_dev:match (INTERNAL) then
        local chain = chain_for (want_dev)
        if chain ~= nil then
          md:set (id, "target.object", "Spa:String", chain)
          log:info ("stream " .. name .. " -> " .. chain)
        end
      end
    end
  end
end

streams_om:connect ("object-added", function () redirect () end)
sinks_om:connect ("object-added", function () apply () end)
sinks_om:connect ("object-removed", function () apply () end)
chains_om:connect ("object-added", function () apply () end)
metadata_om:connect ("object-added", function () apply () end)

metadata_om:activate ()
sinks_om:activate ()
streams_om:activate ()
chains_om:activate ()
