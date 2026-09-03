#!/usr/bin/env python3
"""Derive the levelled film sink from the installed speaker chain.

    gen-levelled-sink.py [--remove]

Writes ~/.config/pipewire/pipewire.conf.d/60-speaker-levelled.conf: the same
14-stage chain with an LSP autogain_stereo in front, published as a SECOND
output called "Speaker (Levelled) - for film". Restart the user session after:

    systemctl --user restart pipewire pipewire-pulse wireplumber

WHY THIS IS A SEPARATE SINK AND NOT PART OF THE MAIN CHAIN.

Netflix and Hotstar arrive near -27 LUFS against YouTube's -14, and the chain
is level-linear below -20 LUFS, so 10.7 dB of that reaches the speaker. A
leveller closes it -- but it cannot be left on for music. Measured as gain
applied within a single track:

    music1   qamp=0  10.8 dB swing      qamp=1  16.4 dB swing
    music2   qamp=0   5.3 dB swing      qamp=1  14.1 dB swing

That is a vocal dropping out and the backing swelling to replace it, and it
was reported from real use before any measurement showed it. It was ONCE
merged into the main chain and had to come back out.

The trade has no middle. Fast enough to fix a film scene change (a loud->quiet
cut otherwise starts ~15 dB low and takes twelve seconds to recover) is fast
enough to ride vocals. Slow enough to leave music alone is slow enough to lag
film. max_amp bounds the pumping but bounds the film correction by the same
amount, and 12 dB is what the gap costs. So: two sinks, and pick one.

qamp = 1 is right HERE, on a film-only output, and wrong in a shared chain.

The volume still has to be set with `spk-vol`, not the sink slider: a sink's
volume lands ahead of the graph, so the leveller sees it and undoes it.
"""
import os, re, sys

SRC = "/etc/pipewire/pipewire.conf.d/50-speaker-tuning.conf"
DST = os.path.expanduser(
    "~/.config/pipewire/pipewire.conf.d/60-speaker-levelled.conf")

NODE = '''                    { type = lv2 name = s0agc plugin = "http://lsp-plug.in/plugins/lv2/autogain_stereo"
                      control = { enabled = 1 level = -17.1
                                  tgrow_l = 10000.0 tfall_l = 10000.0
                                  qamp = 1
                                  max_on = 1 max_amp = 12.0 } }
'''

def main():
    if "--remove" in sys.argv:
        if os.path.exists(DST):
            os.remove(DST); print(f"removed {DST}")
        else:
            print("nothing to remove")
        return
    if not os.path.exists(SRC):
        sys.exit(f"no {SRC} -- run install.sh first")
    s = open(SRC).read()
    if "s0agc" in s:
        sys.exit("the installed chain already has a leveller; nothing to derive")

    # After s0trim, not before: offline-chain.py only feeds per-channel _l/_r
    # source nodes, so a stereo node cannot be the graph input. level is
    # -17.1 rather than -14 because s0trim ahead of it is -3.116 dB.
    anchor = "\n                    # -- stage 1"
    s = s.replace(anchor, "\n" + NODE + anchor, 1)
    old = '                    { output = "s0trim_l:Out" input = "s1sub_l:In" }\n' \
          '                    { output = "s0trim_r:Out" input = "s1sub_r:In" }'
    new = '                    { output = "s0trim_l:Out" input = "s0agc:in_l" }\n' \
          '                    { output = "s0trim_r:Out" input = "s0agc:in_r" }\n' \
          '                    { output = "s0agc:out_l"  input = "s1sub_l:In" }\n' \
          '                    { output = "s0agc:out_r"  input = "s1sub_r:In" }'
    if old not in s:
        sys.exit("could not find the s0trim -> s1sub links; chain layout changed")
    s = s.replace(old, new, 1)

    # Its own identity, so both graphs run side by side, and a priority that
    # does not steal the default.
    s = s.replace('effect_input.speaker-tuning"',  'effect_input.speaker-levelled"')
    s = s.replace('effect_output.speaker-tuning"', 'effect_output.speaker-levelled"')
    s = s.replace('node.description = "Speaker (Tuning)"',
                  'node.description = "Speaker (Levelled) - for film"')
    s = re.sub(r'priority\.session\s*=\s*\d+', 'priority.session = 1', s)

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    open(DST, "w").write(s)
    print(f"wrote {DST}")
    print("restart: systemctl --user restart pipewire pipewire-pulse wireplumber")

main()
