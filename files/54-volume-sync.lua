-- Carry the listening level across an output change, so one slider position
-- means one loudness wherever you are listening.
--
-- WHY. Every sink owns its own volume, and GNOME's slider drives whichever one
-- is currently the default. Nothing carries a level from one to the next, so
-- each output drifts to wherever it was last left: measured on this machine,
-- Speaker (Tuning) sat at 65% while the wired chain sat at 28%, and switching
-- between them changed the loudness by 22 dB with the slider untouched.
-- Reported as "per device volume, can we sync with master volume", 22 Aug 2026.
--
-- WHAT THIS IS NOT. There is no master volume in PipeWire to sync to -- the
-- per-device volume IS the only volume. So this does the reachable thing: when
-- the selection changes, the level you were listening at follows you onto the
-- newly selected output. Switch away and back and you are where you left off,
-- because the level travelled both ways.
--
-- SETTING A VOLUME FROM LUA works, but only in one very specific form:
--
--     mixer:call ("set-volume", id, { volume = v })        -- plain Lua table
--
-- Two other spellings look right and are not. node:set_param("Props", ...) is
-- accepted and does nothing at all. mixer:call with Json.Object { volume = v }
-- RETURNS FALSE -- the one form here that reports its own failure. Both were
-- measured on WirePlumber 0.5.13 against effect_input.tuned-bluetooth, reading
-- the result back with pactl rather than trusting the call.
--
-- The volume is linear here. pactl and GNOME show a cubic percentage, so 60%
-- on the slider is 0.6^3 = 0.216 linear -- do not compare the two by eye.

log = Log.open_topic ("s-volume-sync")

INTERNAL_SINK = "effect_input.speaker-tuning"

-- The ceiling anything but the built-in speaker is held to, matching
-- EXTERNAL_DSP_MAX_LEVEL in external-dsp: the Creative Stage mini is painfully
-- loud above 60%, and carrying a level ONTO headphones or a powered speaker is
-- exactly where an unclamped copy would hurt. The built-in speaker is exempt
-- because it is quiet at full scale and because its slider sits BEFORE the
-- filter graph, where backing off starves the DSP rather than protecting ears.
CAP_LINEAR = 0.6 * 0.6 * 0.6

sinks_om = ObjectManager {
  Interest { type = "node", Constraint { "media.class", "=", "Audio/Sink" } }
}

-- The onboard headphone sink sits behind the wired chain and is hidden from
-- GNOME, so a remembered level on its route is loss nothing can reach: measured
-- at -21.39 dB, held in default-routes as 0.085177, with no slider anywhere
-- that could put it back. The speaker's route was stored at 1.000000, which is
-- the whole reason only headphones sounded quiet. Reported 22 Aug 2026.
--
-- Its level belongs at unity because the GNOME slider already carries the
-- listening level, one stage earlier, on effect_input.tuned-wired.
--
-- THE SPEAKER SINK IS DELIBERATELY NOT PINNED HERE. speaker-dsp writes its
-- volume to level-match the bypass A/B, and holding it at unity would silently
-- break that comparison.
UNITY_SINK = "HiFi__Headphones__sink"

metadata_om = ObjectManager {
  Interest { type = "metadata", Constraint { "metadata.name", "=", "default" } }
}

-- The sink that was default a moment ago, and therefore the one holding the
-- level to carry forward. nil until the first selection is seen, so nothing is
-- written during start-up.
previous = nil

local function default_sink_name (md)
  local cur = md:find (0, "default.audio.sink")
  if cur == nil then return nil end
  local json = Json.Raw (cur)
  if not json:is_object () then return nil end
  local parsed = json:parse ()
  return parsed and parsed["name"] or nil
end

local function node_named (name)
  for n in sinks_om:iterate () do
    if n.properties["node.name"] == name then return n end
  end
  return nil
end

local function capped (name, v)
  if name == INTERNAL_SINK then return v end
  if v > CAP_LINEAR then return CAP_LINEAR end
  return v
end

local function pin_unity ()
  local mixer = Plugin.find ("mixer-api")
  if mixer == nil then return end
  for n in sinks_om:iterate () do
    local name = n.properties["node.name"] or ""
    if name:match (UNITY_SINK) then
      local id = n["bound-id"]
      if id ~= nil then
        local ok, cur = pcall (function () return mixer:call ("get-volume", id) end)
        -- Only ever write a change: the read-back is what stops this from
        -- chasing its own write round the params-changed it causes.
        if ok and cur ~= nil and cur.volume ~= nil and cur.volume < 0.999 then
          mixer:call ("set-volume", id, { volume = 1.0 })
          log:info ("held " .. name .. " at unity, was " .. tostring (cur.volume))
        end
      end
    end
  end
end

local function carry ()
  local md = metadata_om:lookup ()
  if md == nil then return end
  pin_unity ()
  local name = default_sink_name (md)
  if name == nil then return end
  local node = node_named (name)
  if node == nil then return end
  local id = node["bound-id"]
  if id == nil then return end

  if previous ~= nil and previous ~= id then
    local mixer = Plugin.find ("mixer-api")
    if mixer ~= nil then
      -- The sink we are leaving may already be gone -- unplugging a USB
      -- speaker is itself a selection change -- so a failed read here is
      -- ordinary, not an error.
      local ok, from = pcall (function () return mixer:call ("get-volume", previous) end)
      if ok and from ~= nil and from.volume ~= nil then
        local want = capped (name, from.volume)
        mixer:call ("set-volume", id, { volume = want })
        log:info ("carried " .. tostring (from.volume) .. " -> " .. tostring (want)
            .. " onto " .. name)
      end
    end
  end
  previous = id
end

metadata_om:connect ("object-added", function (_, md)
  md:connect ("changed", function (_, subject, key)
    if key == "default.audio.sink" then carry () end
  end)
  carry ()
end)

-- A sink appearing can be the thing that resolves the current selection, so the
-- first carry may only become possible here.
--
-- AND UNITY HAS TO BE RE-ASSERTED, not just set once when the node appears.
-- WirePlumber restores a route's stored volume AFTER object-added, so a single
-- write at that moment is overwritten a beat later and the sink is quietly back
-- at -21 dB. Watching the node's own params is what makes it stick; the
-- read-back inside pin_unity stops that from becoming a ping-pong, and once the
-- value is written WirePlumber saves the new one to default-routes and stops
-- restoring the old.
sinks_om:connect ("object-added", function (_, node)
  local name = node.properties["node.name"] or ""
  if name:match (UNITY_SINK) then
    node:connect ("params-changed", function (_, what)
      if what == "Props" or what == "Route" then pin_unity () end
    end)
  end
  pin_unity ()
  carry ()
end)

metadata_om:activate ()
sinks_om:activate ()
