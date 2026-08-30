-- Give every output its own level, and hold the one node that has no slider at
-- unity.
--
-- WHAT THIS FILE USED TO DO, AND WHY IT STOPPED. Until 30 Aug 2026 this script
-- CARRIED the listening level across an output change: on each selection change
-- it read the level off the sink being left and wrote it onto the sink being
-- chosen, so one slider position meant one loudness wherever you listened.
--
-- The cost of that was not obvious until it was lived with: carrying a level
-- BOTH WAYS means there is only ever ONE level in the system. Every output is
-- overwritten by whichever one you listened to last, so no output can be set to
-- its own level and no output can remember one. Measured 30 Aug 2026, with the
-- Bluetooth receiver selected and sitting at 41%:
--
--     pactl set-sink-volume effect_input.speaker-tuning 55%   -- 55%
--     pactl set-default-sink effect_input.speaker-tuning
--     pactl get-sink-volume effect_input.speaker-tuning       -- 41%
--
-- The built-in speaker was set to 55% and was back at 41% a second later,
-- because selecting it carried the receiver's level onto it. Reported as
-- "master volume same for all connected devices and internal speaker -- it
-- should be separate for each device, and remembered for each device".
--
-- SO THE CARRY IS GONE, AND NOTHING REPLACES IT, because nothing has to.
-- WirePlumber already keeps a level per output; it just kept being written over.
-- The two stores, and which output lands in which:
--
--   effect_input.speaker-tuning    Virtual sinks with no device routes, so
--   effect_input.tuned-wired       node/state-stream restores them, keyed by
--                                  media.name, from ~/.local/state/wireplumber/
--                                  stream-properties. Both chains carry
--                                  state.restore-props = true for this reason;
--                                  the chains that are only ever plumbing carry
--                                  false and come up at unity.
--
--   bluez_output.*                 Real devices, so the level lives in the
--   alsa_output.*                  route's channelVolumes in
--                                  ~/.local/state/wireplumber/default-routes,
--                                  keyed by CARD and route. That key is what
--                                  makes two Bluetooth speakers two levels.
--
-- Both stores were already holding distinct values while the carry was running
-- -- they were simply overwritten with a single one at every switch.
--
-- DO NOT PUT THE CARRY BACK. The two behaviours are exact opposites, both have
-- been asked for, and this is the later of the two: 22 Aug 2026 asked for one
-- level everywhere, 30 Aug 2026 asked for a level per device. If one slider
-- position meaning one loudness is ever wanted again, it wants a DIFFERENT
-- mechanism -- a level offset per output applied on top of a shared level --
-- not a copy that destroys the value it lands on.
--
-- THERE IS ALSO NO CAP ANY MORE. The carry clamped everything but the built-in
-- speaker to 60%, because a level copied ONTO headphones or a powered speaker
-- is a level nobody chose. Nothing is copied onto anything now: every level on
-- every output is one the listener set there. 'external-dsp level' still
-- enforces EXTERNAL_DSP_MAX_LEVEL for the levels it writes itself.
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

log = Log.open_topic ("s-volume-memory")

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

-- UNITY HAS TO BE RE-ASSERTED, not just set once when the node appears.
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
end)

sinks_om:activate ()
