-- Hide the speaker DSP's internal output stream from GNOME's mixer
-- connections, so it never shows up as a phantom entry in App Volumes.
-- Both sinks ("Speaker" = raw hardware, "Speaker (Tuned)" = DSP) stay
-- visible on purpose: on PipeWire 1.6.2 every single-visible-sink
-- arrangement hit a platform bug (smart filters bypass the DSP graph,
-- permission-hiding breaks pulse streams, virtual-sink volume corrupts
-- the chain), so two honest sinks is the robust configuration.
--
-- This user-level copy SHADOWS /usr/local/share/wireplumber/scripts/.

log = Log.open_topic ("s-hide-speaker-tuning")

nodes_om = ObjectManager {
  Interest { type = "node",
    Constraint { "node.name", "matches", "effect_output.speaker-tuning" },
  }
}

-- Match all clients; client.api is only present in the full info
-- properties, not the registry globals that Interest constraints see.
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
    log:info ("hid internal stream " .. tostring (nid) ..
        " from gvc client " .. tostring (cid))
  else
    log:warning ("could not hide node " .. tostring (nid) .. ": " ..
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
