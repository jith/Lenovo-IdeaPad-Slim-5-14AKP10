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

-- A candidate is any sink that is not the built-in speaker and not part of a
-- filter chain. Excluding node.link-group is what stops a chain ever targeting
-- another chain, which is the double-processing case.
local function candidates (pattern)
  local out = {}
  for node in sinks_om:iterate () do
    local props = node.properties
    local name = props["node.name"]
    if name ~= nil
        and props["node.link-group"] == nil
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
      if #found > 0 then
        local want = found[1].name
        if md:find (id, "target.object") ~= want then
          md:set (id, "target.object", "Spa:String", want)
          log:info (tostring (props["node.name"]) .. " -> " .. want)
        end
      end
    end
  end
end

sinks_om:connect ("object-added", function () apply () end)
sinks_om:connect ("object-removed", function () apply () end)
chains_om:connect ("object-added", function () apply () end)
metadata_om:connect ("object-added", function () apply () end)

metadata_om:activate ()
sinks_om:activate ()
chains_om:activate ()
