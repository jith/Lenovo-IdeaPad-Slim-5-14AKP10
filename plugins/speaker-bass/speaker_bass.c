/* One control switches both parallel sends. The caller mixes Cue and Music L/R
 * into the speaker graph before its excursion and true-peak limiters. */
#include <ladspa.h>
#include <math.h>
#include <stdlib.h>

extern const LADSPA_Descriptor *smooth_descriptor(unsigned long);
extern const LADSPA_Descriptor *music_descriptor(unsigned long);

typedef struct {
    const LADSPA_Descriptor *smooth, *music;
    LADSPA_Handle cue, body;
    LADSPA_Data *strength, amount;
} Bass;

static void release(LADSPA_Handle handle) {
    Bass *t = handle;
    if (t->cue) t->smooth->cleanup(t->cue);
    if (t->body) t->music->cleanup(t->body);
    free(t);
}
static LADSPA_Handle create(const LADSPA_Descriptor *desc, unsigned long rate) {
    (void)desc;
    Bass *t = calloc(1, sizeof *t);
    if (!t) return NULL;
    t->smooth = smooth_descriptor(0);
    t->music = music_descriptor(0);
    t->cue = t->smooth->instantiate(t->smooth, rate);
    t->body = t->music->instantiate(t->music, rate);
    if (!t->cue || !t->body) {
        release(t);
        return NULL;
    }
    t->music->connect_port(t->body, 6, &t->amount);
    return t;
}
static void connect(LADSPA_Handle handle, unsigned long i, LADSPA_Data *port) {
    Bass *t = handle;
    if (i < 4) t->smooth->connect_port(t->cue, i, port);
    if (i < 2) t->music->connect_port(t->body, i, port);
    if (i == 3) t->strength = port;
    if (i >= 4) t->music->connect_port(t->body, i - 2, port);
}
static void activate(LADSPA_Handle handle) {
    Bass *t = handle;
    t->smooth->activate(t->cue);
    t->music->activate(t->body);
}
static void process(LADSPA_Handle handle, unsigned long n) {
    Bass *t = handle;
    t->amount = fminf(1.f, fmaxf(0.f, *t->strength / .055f));
    t->smooth->run(t->cue, n);
    t->music->run(t->body, n);
}
#define AI (LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO)
#define AO (LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO)
static const LADSPA_PortDescriptor ports[] = {AI, AI, AO, LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL, AI, AI, AO, AO};
static const char *const names[] = {"Left", "Right", "Cue", "Strength", "Body L", "Body R", "Music L", "Music R"};
static const LADSPA_PortRangeHint hints[] = {{0},{0},{0},
    {LADSPA_HINT_BOUNDED_BELOW|LADSPA_HINT_BOUNDED_ABOVE|LADSPA_HINT_DEFAULT_0,0,.055f},{0},{0},{0},{0}};
static const LADSPA_Descriptor desc = {
    .UniqueID=0x5d5719, .Label="music_and_subbass", .Name="Speaker Bass",
    .Properties=LADSPA_PROPERTY_INPLACE_BROKEN, .Maker="speaker-dsp", .Copyright="None",
    .PortCount=8, .PortDescriptors=ports, .PortNames=names, .PortRangeHints=hints,
    .instantiate=create, .connect_port=connect, .activate=activate, .run=process, .cleanup=release
};
const LADSPA_Descriptor *ladspa_descriptor(unsigned long index) { return index ? NULL : &desc; }
