-- Hide from GNOME what should not be selectable, and only that.
--
-- THE ONBOARD CARD CARRIES BOTH the built-in speaker and the headphone jack, in
-- mutually exclusive UCM profiles. Hiding the card outright -- which is what
-- kept the raw speaker out of GNOME's list -- also hid the headphone jack, so
-- plugging headphones in showed nothing at all. Reported 21 Aug 2026.
--
-- So the card is hidden only while the SPEAKER profile is active. On the
-- headphones profile the card is shown -- its only output port is then
-- Headphones, which is exactly what should be listed -- and "Speaker (Tuning)"
-- is hidden instead, because the built-in speaker is physically unavailable
-- while the jack is occupied and selecting it would mean selecting a chain with
-- no device behind it.
--
-- AND THE JACK WINS. Hiding alone left a one-way door: selecting the internal
-- speaker made WirePlumber switch the card to the Speaker profile to satisfy
-- the chain's target, which removed the Headphones port -- and with the card
-- then hidden there was no way back short of unplugging. Worse, WirePlumber
-- stored that switch as a deliberate choice in default-profile, and a stored
-- profile beats the best available one, so even unplugging and replugging did
-- not bring headphones back. That is the exact trap that made the jack invisible
-- in the first place.
--
-- So while the Headphones route reports available, this puts the card back on
-- the headphones profile. save = false is the whole point of the call: it
-- changes the profile WITHOUT writing it to default-profile, so nothing is
-- remembered and unplugging still falls back to the speaker on its own.

log = Log.open_topic ("s-hide-speaker-tuning")

INTERNAL_SINK = "effect_input.speaker-tuning"
ONBOARD_CARD = "alsa_card.pci-0000_04_00.6"

-- Every chain's output stream: plumbing, never selectable.
nodes_om = ObjectManager {
  Interest { type = "node",
    Constraint { "node.name", "matches", "effect_output.*" },
  }
}

-- The raw built-in speaker, and the external chains' own input sinks, which are
-- hidden behind the real device names by 52-external-target.lua.
raw_om = ObjectManager {
  Interest { type = "node",
    Constraint { "media.class", "=", "Audio/Sink" },
    Constraint { "node.name", "matches", "*HiFi__Speaker__sink" },
  },
  Interest { type = "node",
    Constraint { "media.class", "=", "Audio/Sink" },
    Constraint { "node.name", "matches", "effect_input.tuned-*" },
  },
}

card_om = ObjectManager {
  Interest { type = "device",
    Constraint { "device.name", "equals", ONBOARD_CARD },
  }
}

-- Shown or hidden depending on the profile, so it needs its own manager.
internal_om = ObjectManager {
  Interest { type = "node",
    Constraint { "media.class", "=", "Audio/Sink" },
    Constraint { "node.name", "equals", INTERNAL_SINK },
  }
}

clients_om = ObjectManager {
  Interest { type = "client" }
}

metadata_om = ObjectManager {
  Interest { type = "metadata", Constraint { "metadata.name", "=", "default" } }
}

sinks_om = ObjectManager {
  Interest { type = "node", Constraint { "media.class", "=", "Audio/Sink" } }
}

local function is_gvc_mixer_client (client)
  local props = client["properties"]
  return props ~= nil
      and props["client.api"] == "pipewire-pulse"
      and props["application.id"] == "org.gnome.VolumeControl"
      and props["application.icon-name"] == "multimedia-volume-control"
end

-- The jack, read from the card's routes. This is the only reliable signal:
-- both profiles always report "available", and the Speaker route's own
-- availability is "unknown" on this hardware -- it is the Headphones route
-- flipping to "yes" that says something is plugged in.
local function jack_plugged (dev)
  for p in dev:iterate_params ("EnumRoute") do
    local v = p:parse ()
    if v ~= nil and v.properties ~= nil then
      local pr = v.properties
      if pr.direction == "Output"
          and tostring (pr.name):match ("Headphones")
          and tostring (pr.available) == "yes" then
        return true
      end
    end
  end
  return false
end

local function headphones_profile_index (dev)
  for p in dev:iterate_params ("EnumProfile") do
    local v = p:parse ()
    if v ~= nil and v.properties ~= nil
        and tostring (v.properties.description):match ("Headphones") then
      return v.properties.index
    end
  end
  return nil
end

local function profile_name (dev)
  for p in dev:iterate_params ("Profile") do
    local v = p:parse ()
    if v ~= nil and v.properties ~= nil then
      return v.properties.description or v.properties.name
    end
  end
  return nil
end

-- True when the card is on a profile that carries the built-in speaker. The
-- safe default when the card or its profile cannot be read is TRUE: that keeps
-- the old behaviour, which hides the raw speaker.
local function speaker_active ()
  for dev in card_om:iterate () do
    local n = profile_name (dev)
    if n ~= nil then
      return n:match ("Speaker") ~= nil
    end
  end
  return true
end

local function set_perm (client, obj, allow)
  if not is_gvc_mixer_client (client) then return end
  local id = obj["bound-id"]
  if id == nil then return end
  local ok, err = pcall (function ()
    client:update_permissions { [id] = allow and "rwxm" or "-" }
  end)
  if not ok then
    log:warning ("could not set permission on " .. tostring (id) .. ": "
        .. tostring (err))
  end
end

-- Put the card back on the headphones profile when the jack is occupied.
-- Deliberately does NOT save: a saved profile is what beats jack detection, and
-- writing one here would recreate the bug this exists to fix.
local function honour_jack ()
  for dev in card_om:iterate () do
    if jack_plugged (dev) then
      local n = profile_name (dev)
      if n ~= nil and not n:match ("Headphones") then
        local idx = headphones_profile_index (dev)
        if idx ~= nil then
          log:info ("jack occupied, moving off '" .. n .. "' to profile " ..
              tostring (idx) .. " without saving it")
          dev:set_param ("Profile", Pod.Object {
            "Spa:Pod:Object:Param:Profile", "Profile",
            index = idx,
            save = false,
          })
        end
      end
    end
  end
end

-- Hiding Speaker (Tuning) stops it being CHOSEN; it does not stop it being
-- restored. WirePlumber remembers the last explicit choice in
-- default.configured.audio.sink and reinstates it at every start, so the
-- internal chain came back as the default output with the jack occupied and its
-- own target gone -- which routes a correction built for one measured driver
-- into headphones. The GNOME route is closed and this closes the other one.
local function release_internal_default ()
  local md = metadata_om:lookup ()
  if md == nil then return end
  local plugged = false
  for dev in card_om:iterate () do
    if jack_plugged (dev) then plugged = true end
  end
  if not plugged then return end

  local cur = md:find (0, "default.audio.sink")
  if cur == nil then return end
  local json = Json.Raw (cur)
  if not json:is_object () then return end
  local parsed = json:parse ()
  local name = parsed and parsed["name"]
  if name ~= INTERNAL_SINK then return end

  for node in sinks_om:iterate () do
    local n = node.properties["node.name"]
    if n ~= nil and n:match ("HiFi__Headphones__sink") then
      log:info ("default was " .. INTERNAL_SINK .. " with the jack occupied; "
          .. "moving it to " .. n)
      md:set (0, "default.audio.sink", "Spa:String:JSON",
              Json.Object { name = n }:to_string ())
      return
    end
  end
end

local function refresh ()
  honour_jack ()
  release_internal_default ()
  local spk = speaker_active ()
  log:info ("speaker profile active: " .. tostring (spk))
  for client in clients_om:iterate () do
    if is_gvc_mixer_client (client) then
      for node in nodes_om:iterate () do set_perm (client, node, false) end
      for node in raw_om:iterate () do set_perm (client, node, false) end
      -- The card is what carries the headphone port, so it is only hidden
      -- while the speaker profile owns the card.
      for dev in card_om:iterate () do set_perm (client, dev, not spk) end
      -- And Speaker (Tuning) is only meaningful while that profile is active.
      for node in internal_om:iterate () do set_perm (client, node, spk) end
    end
  end
end

clients_om:connect ("object-added", function () refresh () end)
nodes_om:connect ("object-added", function () refresh () end)
raw_om:connect ("object-added", function () refresh () end)
internal_om:connect ("object-added", function () refresh () end)
card_om:connect ("object-added", function (_, dev)
  -- The profile changing is the event that matters most, and it arrives on the
  -- device as a param rather than as a property change.
  dev:connect ("params-changed", function (_, name)
    if name == "Profile" then refresh () end
  end)
  refresh ()
end)

metadata_om:connect ("object-added", function () refresh () end)
sinks_om:connect ("object-added", function () refresh () end)

metadata_om:activate ()
sinks_om:activate ()
clients_om:activate ()
nodes_om:activate ()
raw_om:activate ()
internal_om:activate ()
card_om:activate ()
