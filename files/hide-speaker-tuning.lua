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

local function is_gvc_mixer_client (client)
  local props = client["properties"]
  return props ~= nil
      and props["client.api"] == "pipewire-pulse"
      and props["application.id"] == "org.gnome.VolumeControl"
      and props["application.icon-name"] == "multimedia-volume-control"
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

local function refresh ()
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

clients_om:activate ()
nodes_om:activate ()
raw_om:activate ()
internal_om:activate ()
card_om:activate ()
