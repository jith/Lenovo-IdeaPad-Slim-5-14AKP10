-- Keep the External (Tuning) chain pointed at whichever non-internal output is
-- currently the best one: a Bluetooth speaker, earbuds, wired headphones, HDMI
-- or a USB speaker.
--
-- WHY A SCRIPT AND NOT filter.smart. WirePlumber 0.5 smart filters are the
-- feature built for this and they link correctly, but on 0.5.13 the DSP is not
-- applied -- measured, see the table in 52-external-tuning.conf. So the chain
-- is an ordinary filter-chain with target.object, and this script supplies the
-- target at runtime.
--
-- WHY IT MATTERS THAT THIS RUNS. With no target resolved, PipeWire routes the
-- chain's playback stream to the default sink, which is the INTERNAL chain --
-- verified 20 Aug 2026. Everything would then be processed twice, by two
-- chains tuned for different speakers. node.autoconnect = false blocks that but
-- also blocks this script's retarget, so the guard has to be that this runs.

log = Log.open_topic ("s-external-tuning")

INTERNAL_SINK = "alsa_output.pci%-0000_04_00%.6%.HiFi__Speaker__sink"
FILTER_OUT    = "effect_output.external-tuning"
UNSET         = "__external-tuning-unset__"

metadata_om = ObjectManager {
  Interest { type = "metadata", Constraint { "metadata.name", "=", "default" } }
}

sinks_om = ObjectManager {
  Interest { type = "node", Constraint { "media.class", "=", "Audio/Sink" } }
}

filter_om = ObjectManager {
  Interest { type = "node", Constraint { "node.name", "=", FILTER_OUT } }
}

-- A sink counts as "external" when it is neither the built-in speaker nor part
-- of a filter chain. Excluding node.link-group keeps us from ever targeting our
-- own chain or the internal one, which is what would create the double-DSP loop.
local function is_external (props)
  local name = props["node.name"]
  if name == nil then return false end
  if name:match (INTERNAL_SINK) then return false end
  if name:match ("^effect_") then return false end
  if props["node.link-group"] ~= nil then return false end
  return true
end

-- The device the listener last chose, written by `external-dsp device`. It is
-- read here rather than reapplied by a login service, because this script
-- already runs whenever the graph is rebuilt and knows when the device is
-- actually present.
local function remembered ()
  local home = os.getenv ("HOME")
  if home == nil then return nil end
  local f = io.open (home .. "/.local/state/external-dsp/device", "r")
  if f == nil then return nil end
  local name = f:read ("l")
  f:close ()
  if name == nil or name == "" then return nil end
  return name
end

local function pick ()
  local best, best_prio = nil, -1
  for node in sinks_om:iterate () do
    local props = node.properties
    if is_external (props) then
      local prio = tonumber (props["priority.session"]) or 0
      if prio > best_prio then
        best, best_prio = props["node.name"], prio
      end
    end
  end
  return best
end

-- Is this name still a connected external sink?
local function still_present (name)
  if name == nil or name == UNSET then return false end
  for node in sinks_om:iterate () do
    local props = node.properties
    if is_external (props) and props["node.name"] == name then return true end
  end
  return false
end

local function apply ()
  local md = metadata_om:lookup ()
  if md == nil then return end
  local out = filter_om:lookup ()
  if out == nil then return end
  local id = out["bound-id"]
  if id == nil then return end

  -- Keep whatever is already selected as long as it is still connected. With
  -- more than one external device attached -- a USB speaker and earbuds, say --
  -- GNOME cannot choose between them, because this branch hides the raw
  -- devices; `external-dsp device` is the chooser, and re-picking by priority
  -- on every event would silently undo the listener's choice. Only when the
  -- selected device goes away does priority decide the replacement.
  -- The remembered choice wins outright whenever that device is present, and
  -- is checked BEFORE the current target. Bluetooth takes several seconds to
  -- reconnect after a restart, so the first pass runs with the earbuds absent,
  -- falls back to priority, and settles on whatever else is attached -- and a
  -- "keep the current target while it is still valid" rule then locks that in
  -- for good, exactly when the earbuds finally appear. Checking the file first
  -- makes the listener's choice authoritative rather than a race.
  local current = md:find (id, "target.object")
  local want = remembered ()
  if still_present (want) then
    if current ~= want then
      md:set (id, "target.object", "Spa:String", want)
      log:info ("External (Tuning) -> " .. want .. " (remembered)")
    end
    return
  end

  if still_present (current) then return end

  local target = pick ()
  if target == nil then
    -- Nothing external connected. Park on a name that resolves to nothing
    -- rather than leaving a stale device pinned.
    md:set (id, "target.object", "Spa:String", UNSET)
    log:info ("no external sink; parked External (Tuning)")
  else
    md:set (id, "target.object", "Spa:String", target)
    log:info ("External (Tuning) -> " .. target)
  end
end

sinks_om:connect ("object-added",   function () apply () end)
sinks_om:connect ("object-removed", function () apply () end)
filter_om:connect ("object-added",  function () apply () end)
metadata_om:connect ("object-added", function () apply () end)

metadata_om:activate ()
sinks_om:activate ()
filter_om:activate ()
