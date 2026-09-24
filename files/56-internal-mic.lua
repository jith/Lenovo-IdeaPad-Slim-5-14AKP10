-- Make the built-in microphone the default source.
--
-- THE "DIGITAL MICROPHONE" IS NOT A MICROPHONE. UCM sees the ACP PDM card and
-- offers it as Mic1, but nothing is wired to it: it records a stuck full-scale
-- signal, DC offset -0.9999 and 0 dB mean, whatever is said. Whisper turned
-- that into "E aí" and "Thank you." Found 14 Sep 2026. 56-internal-mic.conf
-- disables the node, so it is never offered.
--
-- THE REAL MIC IS THE CODEC'S ANALOG INPUT, UCM Mic2 "Stereo Microphone". The
-- SN6140 moves its ADC between the built-in analog mic and the headset jack by
-- itself, but UCM's generic HDA profile models the input as a jack mic only and
-- ties it to "Mic Jack". With nothing plugged in the route reads "not
-- available", and WirePlumber's rescan drops every node whose route says so
-- before any hook sees it. `wpctl set-default` is stored and then ignored, and
-- with Mic1 gone the default fell to a sink monitor: -91 dB of silence.
--
-- IT IS NOT ONLY A SELECTION. Selecting Mic2 itself fixed pactl and nothing
-- else: Chromium and GNOME Settings leave out a source whose ports are all
-- unavailable, so Brave reported no microphone at all, 24 Sep 2026. So the
-- default is "internal-mic", a portless virtual source in front of Mic2, loaded
-- by /etc/pipewire/pipewire.conf.d/56-internal-mic-source.conf.
--
-- This hook runs after WirePlumber's own choice and before that choice is
-- applied, and it steps in only when that choice is not a real microphone --
-- nothing, or a sink monitor -- and was not picked deliberately. A USB or
-- Bluetooth mic is available, is chosen normally, and is left alone.

log = Log.open_topic ("s-internal-mic")

INTERNAL_MIC = "internal-mic"

mic_om = ObjectManager {
  Interest { type = "node",
    Constraint { "node.name", "equals", INTERNAL_MIC },
  }
}

SimpleEventHook {
  name = "speaker-dsp/internal-mic-default",
  after = { "default-nodes/find-best-default-node",
            "default-nodes/find-selected-default-node",
            "default-nodes/find-stored-default-node" },
  before = "default-nodes/apply-default-node",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-default-node" },
      Constraint { "default-node.type", "=", "audio.source" },
    },
  },
  execute = function (event)
    if mic_om:lookup () == nil then return end

    local selected = event:get_data ("selected-node")
    if selected == INTERNAL_MIC then return end

    if selected ~= nil then
      local available = event:get_data ("available-nodes")
      available = available and available:parse () or {}
      for _, props in ipairs (available) do
        -- A source that is really a source was chosen on merit. Sink monitors
        -- are in the candidate list only because they have output ports.
        if props ["node.name"] == selected
            and props ["media.class"] ~= "Audio/Sink" then
          return
        end
      end

      -- A monitor the user picked on purpose stays picked.
      local md_om = event:get_source ():call ("get-object-manager", "metadata")
      local md = md_om:lookup { Constraint { "metadata.name", "=", "default" } }
      local cfg = md and md:find (0, "default.configured.audio.source")
      if cfg ~= nil and Json.Raw (cfg):parse ().name == selected then return end
    end

    log:info ("default source " .. tostring (selected)
        .. " is not a microphone, selecting " .. INTERNAL_MIC)
    event:set_data ("selected-node", INTERNAL_MIC)
  end
}:register ()

-- The node can appear after the first rescan has already run, and nothing
-- else would ask again until a device changed.
mic_om:connect ("object-added", function ()
  local source = Plugin.find ("standard-event-source")
  if source then source:call ("schedule-rescan", "default-nodes") end
end)

mic_om:activate ()
