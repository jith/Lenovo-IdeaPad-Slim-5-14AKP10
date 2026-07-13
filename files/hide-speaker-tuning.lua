-- Hide the internal "Speaker Tuning DSP" filter nodes from PulseAudio
-- clients (GNOME Settings, gnome-shell volume menu, pactl, pavucontrol),
-- so only the physical Speaker output is listed as a device.
--
-- WirePlumber and the PipeWire core keep full access, so audio is still
-- routed through the DSP; this only removes the virtual nodes from what
-- pulse clients can see. If this script ever fails, audio keeps working -
-- the filter nodes just become visible again.
--
-- Paired with:
--   ~/.config/pipewire/pipewire.conf.d/50-speaker-tuning.conf   (the DSP)
--   ~/.config/wireplumber/wireplumber.conf.d/50-hide-speaker-tuning.conf

log = Log.open_topic ("s-hide-speaker-tuning")

-- The two internal nodes created by 50-speaker-tuning.conf
nodes_om = ObjectManager {
  Interest { type = "node",
    Constraint { "node.name", "matches", "effect_*.speaker-tuning" },
  }
}

-- Match all clients; client.api is only present in the full info
-- properties, not the registry globals that Interest constraints see,
-- so we filter inside the callbacks instead (like access scripts do).
clients_om = ObjectManager {
  Interest { type = "client" }
}

-- Only blind the GNOME mixer-control (libgvc) connections: the device
-- lists in GNOME Settings and the shell volume menu. These connections
-- never own playback streams, so hiding nodes from them is safe.
-- IMPORTANT: never hide from ordinary pulse clients - their playback
-- streams get linked to the DSP node by WirePlumber, and a client whose
-- stream is linked to a node it cannot see times out (silent audio,
-- GNOME Settings crash). Learned the hard way.
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
    log:info ("hid DSP node " .. tostring (nid) ..
        " from pulse client " .. tostring (cid))
  else
    log:warning ("could not hide DSP node " .. tostring (nid) .. ": " ..
        tostring (err))
  end
end

clients_om:connect ("object-added", function (om, client)
  for node in nodes_om:iterate () do
    hide (client, node)
  end
end)

nodes_om:connect ("object-added", function (om, node)
  for client in clients_om:iterate () do
    hide (client, node)
  end
end)

clients_om:activate ()
nodes_om:activate ()
