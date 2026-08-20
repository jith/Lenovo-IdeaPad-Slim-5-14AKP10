-- Hide the raw speaker sink and the DSP's internal output stream from GNOME's
-- mixer connections. Apps may still use the virtual Speaker (Tuning) sink;
-- pactl and pavucontrol continue to show every node.

log = Log.open_topic ("s-hide-speaker-tuning")

-- Both chains' output streams: effect_output.speaker-tuning (internal) and
-- effect_output.external-tuning (Bluetooth, headphones, HDMI, USB). These are
-- plumbing -- the sinks apps actually pick, effect_input.*, stay visible.
nodes_om = ObjectManager {
  Interest { type = "node",
    Constraint { "node.name", "matches", "effect_output.*-tuning" },
  }
}

-- Every REAL output device: the built-in speaker and headphone jack, USB
-- speakers, Bluetooth, HDMI. GNOME should offer the two tuned sinks and
-- nothing else, so that whatever is selected is always processed. The devices
-- are still there -- pactl and pavucontrol show them, and External (Tuning)
-- follows whichever one is active via 52-external-target.lua.
raw_om = ObjectManager {
  Interest { type = "node",
    Constraint { "media.class", "=", "Audio/Sink" },
    Constraint { "node.name", "matches", "alsa_output.*" },
  },
  Interest { type = "node",
    Constraint { "media.class", "=", "Audio/Sink" },
    Constraint { "node.name", "matches", "bluez_output.*" },
  },
}

-- GNOME derives output entries from card PORTS as well as from sink nodes, so
-- hiding the sinks alone is not enough -- a USB speaker still shows up as
-- "Analog Output" and "Digital Output" entries from its card. Hide every audio
-- card for the same reason the sinks are hidden: the two tuned sinks are the
-- only outputs that should be selectable, so that whatever is chosen is always
-- processed.
--
-- This covers the onboard card, HDMI, USB and Bluetooth. An earlier version
-- named the onboard card alone and deliberately left HDMI visible; that made
-- sense when only the internal speaker was tuned, and stopped making sense once
-- External (Tuning) covered everything else.
card_om = ObjectManager {
  Interest { type = "device",
    Constraint { "device.name", "matches", "alsa_card.*" },
  },
  Interest { type = "device",
    Constraint { "device.name", "matches", "bluez_card.*" },
  },
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

local function hide (client, node)
  if not is_gvc_mixer_client (client) then
    return
  end
  local nid = node["bound-id"]
  local cid = client["bound-id"]
  if nid == nil or cid == nil then
    return
  end
  local ok, err = pcall (function ()
    client:update_permissions { [nid] = "-" }
  end)
  if ok then
    log:info ("hid node " .. tostring (nid) .. " from gvc client " ..
        tostring (cid))
  else
    log:warning ("could not hide node " .. tostring (nid) .. ": " ..
        tostring (err))
  end
end

clients_om:connect ("object-added", function (om, client)
  for node in nodes_om:iterate () do
    hide (client, node)
  end
  for node in raw_om:iterate () do
    hide (client, node)
  end
  for dev in card_om:iterate () do
    hide (client, dev)
  end
end)

nodes_om:connect ("object-added", function (om, node)
  for client in clients_om:iterate () do
    hide (client, node)
  end
end)

raw_om:connect ("object-added", function (om, node)
  for client in clients_om:iterate () do
    hide (client, node)
  end
end)

card_om:connect ("object-added", function (om, dev)
  for client in clients_om:iterate () do
    hide (client, dev)
  end
end)

clients_om:activate ()
nodes_om:activate ()
raw_om:activate ()
card_om:activate ()
