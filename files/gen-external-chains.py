#!/usr/bin/env python3
"""Write one External (Tuning) filter chain per connected external device.

    gen-external-chains.py [OUT.conf]

WHY ONE CHAIN PER DEVICE. GNOME builds its output list from sinks, and this
setup hides the raw devices so nothing can be played untuned. That left a single
"External (Tuning)" entry with no way to choose between, say, a USB speaker and
earbuds. WirePlumber's smart filters would have solved it natively -- they link
a chain in front of a device automatically -- but on 0.5.13 they link and do not
process (measured; see 52-external-tuning.conf). So each device gets a real
chain of its own, named after it, and GNOME does the switching.

WHY GENERATED AND NOT HAND-WRITTEN. The chain is 150 lines of measured settings
and there must be one copy per device, identical except for its identity and
target. Generating them keeps a single source of truth: edit the template, run
this, and every device picks the change up.

WHY IT IS NOT FULLY AUTOMATIC. PipeWire loads filter chains from config at
startup, and modules loaded at runtime with pw-cli die with the client
(verified), so a chain cannot be conjured when a device appears without a
process that stays running.

What IS automatic: a chain is generated for every device known at the time, and
53-hide-absent-tuned.lua hides the ones whose device is not currently connected.
So connecting any device this has already seen makes its entry appear in GNOME
by itself, with no regeneration and no restart. Only a genuinely new device --
one paired since the last run -- needs this run again.

Each chain carries speaker-dsp.device naming the device it belongs to, which is
how that script knows which sink to hide.
"""
import re
import subprocess
import sys
import os

def _template():
    """Installed copy first, then the repo checkout, so this works either way."""
    env = os.environ.get("SPEAKER_DSP_TEMPLATE")
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for path in (env,
                 "/usr/local/share/speaker-dsp/52-external-tuning.conf",
                 os.path.join(root, "files", "52-external-tuning.conf")):
        if path and os.path.exists(path):
            return path
    sys.stderr.write("cannot find 52-external-tuning.conf\n")
    sys.exit(1)


TEMPLATE = None

INTERNAL = "HiFi__Speaker__sink"


# One chain per CLASS of device, not per device. The class is matched against
# node.name by 52-external-target.lua, which points each chain at whichever
# device currently matches -- so a newly paired speaker or headset is picked up
# with nothing to run and nothing watching. Naming the chains after the class
# rather than the device is the price: GNOME shows "Bluetooth (Tuning)" and not
# "OPPO Enco Buds", because a node cannot be renamed at runtime.
#
# Two classes cover everything this machine can output to. The internal speaker
# is excluded by 50-speaker-tuning.conf owning it already.
CLASSES = [
    ("bluetooth", "Bluetooth (Tuning)", "^bluez_output%."),
    ("wired", "Headphones / Wired (Tuning)", "^alsa_output%."),
]


def slug(name):
    """A short, stable, filename-safe id for a device node name."""
    s = name.split(".", 1)[-1]
    s = re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-").lower()
    return s[:40]


def main():
    dest = sys.argv[1] if len(sys.argv) > 1 else "-"
    text = open(_template()).read()

    # The template is `context.modules = [ <one module> ]`. Take the module and
    # repeat it, so the measured graph inside stays the single source of truth.
    start = text.index("context.modules = [")
    head = text[:start]
    body = text[start + len("context.modules = ["):]
    body = body.rstrip()
    assert body.endswith("]"), "template is not a single context.modules array"
    module = body[:-1].strip()

    blocks = []
    for sid, desc, pattern in CLASSES:
        m = module
        m = m.replace('node.description = "External (Tuning)"',
                      'node.description = "%s"' % desc.replace('"', "'"))
        m = m.replace('node.name = "effect_input.external-tuning"',
                      'node.name = "effect_input.tuned-%s"' % sid)
        m = m.replace('node.name = "effect_output.external-tuning"',
                      'node.name = "effect_output.tuned-%s"\n'
                      '                speaker-dsp.match = "%s"' % (sid, pattern))
        m = m.replace("node.link-group = external-tuning",
                      "node.link-group = tuned-%s" % sid)
        # No target here: 52-external-target.lua sets it to whichever device
        # currently matches speaker-dsp.match. A placeholder that resolves to
        # nothing would not be safer -- PipeWire falls back to the default sink
        # either way, which is another tuned sink, so the script running is what
        # keeps a stream from being processed twice. Verified 20 Aug 2026.
        blocks.append(m)

    with (open(dest, "w") if dest != "-" else sys.stdout) as f:
        f.write(head)
        f.write("# GENERATED by gen-external-chains.py -- do not edit.\n")
        f.write("# Edit files/52-external-tuning.conf and re-run install.sh.\n")
        f.write("# One chain per class of output:\n")
        for sid, desc, pattern in CLASSES:
            f.write("#   %-30s %s\n" % (desc, pattern))
        f.write("context.modules = [\n")
        f.write("\n".join(blocks))
        f.write("\n]\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
