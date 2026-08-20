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

raw_om = ObjectManager {
  Interest { type = "node",
    Constraint { "node.name", "matches", "*HiFi__Speaker__sink" },
  }
}

-- GNOME also derives output entries from card ports, so hide this onboard
-- speaker card while leaving other devices such as HDMI visible.
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
