-- Hide from GNOME what should not be selectable, and only that.
--
-- THE ONBOARD CARD CARRIES BOTH the built-in speaker and the headphone jack, in
-- mutually exclusive UCM profiles. Hiding the card outright -- which is what
-- kept the raw speaker out of GNOME's list -- also hid the headphone jack, so
-- plugging headphones in showed nothing at all. Reported 21 Aug 2026.
--
-- SHOWING THE CARD WAS THE WRONG WAY TO SHOW THE JACK. GNOME Settings builds
-- its output dropdown from CARD PORTS, not from sink ports -- that is how it
-- offers a port belonging to an inactive profile -- and this card carries
-- [Out] Speaker and [Out] Headphones on the same card whatever profile is
-- live. So making the card visible put the raw "Speaker" port back in the list
-- next to "Speaker (Tuning)": two entries for the built-in speaker, one of them
-- bypassing the DSP entirely. Reported as a duplicated name in both the shell
-- toggle and Settings, 21 Aug 2026.
--
-- The card therefore stays hidden always, as it was. What is shown instead is
-- the headphone SINK, which exists only on the headphones profile and carries
-- one port. A sink is listed on its own, so nothing has to expose the card.
--
-- "Speaker (Tuning)" is hidden while the jack is occupied, because the built-in
-- speaker is physically unavailable then and selecting it would mean selecting
-- a chain with no device behind it.
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

-- Whether Speaker (Tuning) should be offered. Decided by whether the raw
-- speaker sink EXISTS, not by the jack and not by the profile name.
--
-- Keying it off the jack left a gap with no output at all: with the jack in but
-- the card still on the Speaker profile -- which is exactly what a remembered
-- profile produces -- Speaker (Tuning) was hidden because the jack was in, the
-- headphone sink did not exist because the profile was Speaker, and the raw
-- speaker is always hidden. GNOME was served nothing selectable.
--
-- Existence cannot produce that gap: whichever profile is live, exactly one of
-- the two sinks is there, so exactly one entry is offered.
local function speaker_selectable ()
  for node in sinks_om:iterate () do
    local n = node.properties["node.name"]
    if n ~= nil and n:match ("HiFi__Speaker__sink") then return true end
  end
  return false
end

-- EVERY permission write is an event to the client, and gvc builds its device
-- list from those events. refresh() runs about twenty times while the graph
-- settles, so re-asserting the same permission each time produced a storm of
-- new/remove pairs on the same sink. Only ever send a change.
--
-- Keyed per client and CLEARED WHEN THE CLIENT GOES AWAY, because PipeWire
-- reuses client ids: one flat table meant a new client inheriting a retired id
-- hit the previous client's entry, the hide was skipped as already applied, and
-- that client saw the entire graph.
applied = {}

local function set_perm (client, obj, allow)
  if not is_gvc_mixer_client (client) then return end
  local id = obj["bound-id"]
  local cid = client["bound-id"]
  if id == nil or cid == nil then return end
  local seen = applied[cid]
  if seen == nil then seen = {}; applied[cid] = seen end
  if seen[id] == allow then return end
  local ok, err = pcall (function ()
    client:update_permissions { [id] = allow and "rwxm" or "-" }
  end)
  if ok then
    seen[id] = allow
  else
    log:warning ("could not set permission on " .. tostring (id) .. ": "
        .. tostring (err))
  end
end

-- BOTH the speaker and the headphones are listed while the jack is occupied, so
-- the choice is the listener's. The two entries are the two virtual chains,
-- because they always exist: the real headphone sink exists only on the
-- headphones profile, so it cannot be an entry you can switch BACK to once the
-- card has moved to the speaker.
--
--   Speaker (Tuning)            effect_input.speaker-tuning
--   Headphones / Wired (Tuning) effect_input.tuned-wired
--
-- The card profile then follows whichever one is selected. Nothing is forced
-- against the listener any more -- an earlier version put the card back on the
-- headphones profile whenever the jack was in, which made choosing the speaker
-- a one-way door.
local function profile_index_matching (dev, want)
  for p in dev:iterate_params ("EnumProfile") do
    local v = p:parse ()
    if v ~= nil and v.properties ~= nil
        and tostring (v.properties.description):match (want) then
      return v.properties.index
    end
  end
  return nil
end

local function set_profile (dev, want)
  local cur = profile_name (dev)
  if cur ~= nil and cur:match (want) then return end
  local idx = profile_index_matching (dev, want)
  if idx == nil then return end
  log:info ("selection wants '" .. want .. "', moving off '" .. tostring (cur) .. "'")
  -- save = false: a remembered profile beats jack detection, and writing one
  -- here is what previously left the jack unnoticed after a replug.
  dev:set_param ("Profile", Pod.Object {
    "Spa:Pod:Object:Param:Profile", "Profile", index = idx, save = false,
  })
end

local function default_sink_name (md)
  local cur = md:find (0, "default.audio.sink")
  if cur == nil then return nil end
  local json = Json.Raw (cur)
  if not json:is_object () then return nil end
  local parsed = json:parse ()
  return parsed and parsed["name"] or nil
end

-- Exactly the set apply_to_client refuses to show, expressed once so the two
-- cannot drift apart.
local function hidden_from_gnome (name, plugged)
  if name:match ("^effect_output%.") then return true end
  if name:match ("HiFi__Speaker__sink") then return true end
  if name:match ("HiFi__Headphones__sink") then return true end
  if name:match ("^effect_input%.tuned%-") then
    return not (plugged and name == "effect_input.tuned-wired")
  end
  return false
end

-- A SINK THAT IS HIDDEN FROM GNOME MUST NEVER BE THE DEFAULT. Two different
-- things set the two: permissions are set here, the default is restored by
-- WirePlumber from default-nodes, and nothing kept them in step.
--
-- Pulling the jack out hid effect_input.tuned-wired again but left it as the
-- default sink, and its pattern ^alsa_output%. then matches the built-in
-- speaker -- so audio really did keep playing, through the wired chain, out of
-- the speaker. GNOME, served only Speaker (Tuning), pointed its slider at that
-- chain instead. The slider moved a sink with no stream in it: audio unchanged,
-- while the headphone case worked because there the visible sink and the
-- default were the same node. Reported as "volume slider not working on the
-- internal speaker, working fine on headphones", 22 Aug 2026.
--
-- default.configured.audio.sink is the key to write, not default.audio.sink:
-- the configured one is the selection, and WirePlumber recomputes the other
-- from it. Writing only default.audio.sink is undone on the next pass.
local function release_hidden_default ()
  local md = metadata_om:lookup ()
  if md == nil then return end
  local name = default_sink_name (md)
  if name == nil or name == INTERNAL_SINK then return end

  local plugged = false
  for dev in card_om:iterate () do plugged = jack_plugged (dev) end
  if not hidden_from_gnome (name, plugged) then return end

  -- Plain find, not a pattern: "speaker-tuning" read as a pattern makes the
  -- hyphen a lazy quantifier and stops matching itself.
  local cfg = md:find (0, "default.configured.audio.sink")
  if cfg ~= nil and string.find (cfg, INTERNAL_SINK, 1, true) then return end

  log:info ("default sink " .. name .. " is hidden from GNOME, releasing to "
      .. INTERNAL_SINK)
  md:set (0, "default.configured.audio.sink", "Spa:String:JSON",
      '{"name":"' .. INTERNAL_SINK .. '"}')
end

local function follow_selection ()
  local md = metadata_om:lookup ()
  if md == nil then return end
  local name = default_sink_name (md)
  if name == nil then return end

  for dev in card_om:iterate () do
    if name == INTERNAL_SINK then
      set_profile (dev, "Speaker")
    elseif name == "effect_input.tuned-wired" and jack_plugged (dev) then
      set_profile (dev, "Headphones")
    end
  end
end

-- Apply to ONE client. Takes the client as an argument rather than iterating
-- clients_om, because a client is not yet in the manager when its own
-- object-added fires -- iterating applied nothing to the client that had just
-- connected, so every client appearing after start-up saw the whole graph.
local function apply_to_client (client)
  if not is_gvc_mixer_client (client) then return end
  if card_om:lookup () == nil then return end

  local plugged = false
  for dev in card_om:iterate () do plugged = jack_plugged (dev) end

  -- Chain outputs are plumbing, never selectable.
  for node in nodes_om:iterate () do set_perm (client, node, false) end

  -- raw_om holds the raw speaker sink and the tuned chain inputs.
  -- effect_input.tuned-wired is the HEADPHONE entry while the jack is in, so it
  -- is the one member that is shown rather than hidden. It is used instead of
  -- the real headphone sink because that sink exists only on the headphones
  -- profile -- it could not be something to switch BACK to once the card had
  -- moved to the speaker.
  for node in raw_om:iterate () do
    local n = node.properties["node.name"] or ""
    set_perm (client, node, plugged and n == "effect_input.tuned-wired")
  end

  -- The real headphone sink stays hidden: tuned-wired stands in front of it,
  -- and listing both is the duplicate all over again.
  for node in sinks_om:iterate () do
    local n = node.properties["node.name"] or ""
    if n:match ("HiFi__Headphones__sink") then set_perm (client, node, false) end
  end

  -- The card carries the raw Speaker port, which GNOME would list beside
  -- Speaker (Tuning).
  for dev in card_om:iterate () do set_perm (client, dev, false) end

  -- Always listed: selecting it moves the card to the speaker profile.
  for node in internal_om:iterate () do set_perm (client, node, true) end
end

local function refresh ()
  -- Until the card is known, every answer here is a guess that will be
  -- corrected a moment later -- and a correction is a remove event. Wait.
  if card_om:lookup () == nil then return end
  release_hidden_default ()
  follow_selection ()
  for client in clients_om:iterate () do apply_to_client (client) end
end

-- A client gets its permissions applied directly, never by iterating: it is not
-- in clients_om yet when its own object-added fires.
clients_om:connect ("object-added", function (_, client)
  apply_to_client (client)
end)

clients_om:connect ("object-removed", function (_, client)
  local cid = client["bound-id"]
  if cid ~= nil then applied[cid] = nil end
end)

-- Anything newly appearing has to be hidden from every client already connected.
nodes_om:connect ("object-added", function () refresh () end)
raw_om:connect ("object-added", function () refresh () end)
internal_om:connect ("object-added", function () refresh () end)
metadata_om:connect ("object-added", function (_, md)
  -- WirePlumber restores default.configured.audio.sink well AFTER the metadata
  -- object appears, so reacting only to it appearing missed the restore
  -- entirely: the card was corrected to the headphones profile, GNOME was
  -- offered the headphones, and the actual default stayed on the hidden
  -- internal chain. That is what "plugged in but still on speaker" was.
  md:connect ("changed", function (_, subject, key)
    if key == "default.audio.sink" then refresh () end
  end)
  refresh ()
end)
sinks_om:connect ("object-added", function () refresh () end)

card_om:connect ("object-added", function (_, dev)
  -- The profile changing is the event that matters most, and it arrives on the
  -- device as a param rather than as a property change.
  -- PLUGGING A JACK CHANGES ROUTES, NOT THE PROFILE. Listening only for
  -- "Profile" meant a jack going in was never noticed: it worked the first time
  -- only because WirePlumber switched the profile itself, and stopped working
  -- as soon as a remembered profile kept it on Speaker.
  dev:connect ("params-changed", function (_, name)
    if name == "Profile" or name == "Route" or name == "EnumRoute" then
      refresh ()
    end
  end)
  refresh ()
end)

metadata_om:activate ()
sinks_om:activate ()
clients_om:activate ()
nodes_om:activate ()
raw_om:activate ()
internal_om:activate ()
card_om:activate ()
