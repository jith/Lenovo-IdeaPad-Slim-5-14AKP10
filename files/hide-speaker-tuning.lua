-- Hide the raw speaker sink and the DSP's internal output stream from GNOME's
-- mixer connections. Apps may still use the virtual Speaker (Tuning) sink;
-- pactl and pavucontrol continue to show every node.

log = Log.open_topic ("s-hide-speaker-tuning")

-- Every chain's output stream: effect_output.speaker-tuning for the internal
-- speaker, and one effect_output.tuned-<device> per external device. These are
-- plumbing -- the sinks apps actually pick, effect_input.*, stay visible, and
-- those now carry the real device names.
nodes_om = ObjectManager {
  Interest { type = "node",
    Constraint { "node.name", "matches", "effect_output.*" },
  }
}

-- GNOME lists the REAL devices -- "OPPO Enco Buds", "Creative Stage SE mini" --
-- and the tuned sinks are hidden behind them: 52-external-target.lua moves any
-- stream sent to an external device into that device's chain instead. So the
-- names are the devices' own, and everything is still processed.
--
-- Hidden here: the built-in speaker (owned by 50-speaker-tuning.conf, which
-- GNOME shows as "Speaker (Tuning)"), and the external chains' own input sinks,
-- which are plumbing and would otherwise appear alongside the devices.
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

-- GNOME derives output entries from card PORTS as well as from sink nodes, so
-- the onboard card is hidden too -- otherwise the built-in speaker reappears as
-- a card port even with its sink hidden. Other cards stay visible: their
-- devices are what GNOME should be listing.
card_om = ObjectManager {
  Interest { type = "device",
    Constraint { "device.name", "equals", "alsa_card.pci-0000_04_00.6" },
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
