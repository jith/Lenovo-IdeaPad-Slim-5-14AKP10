/* Parallel stereo send for the bass and its existing audible harmonics.
   Key from the source. Take the audio from the body bus, before the limiter. */
#include <ladspa.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct { double b0, b1, b2, a1, a2; } Coeff;
typedef struct { double z1, z2; } Filter;
typedef struct {
    Filter hp1, hp2, hp3, lp, sub1, sub2, body, partials;
    double low; /* One-pole low pass on the body bus. */
} Channel;
typedef struct {
    Channel channels[2];
    double fast, slow, sub, low_fraction, key_power, gain;
} State;
typedef struct {
    LADSPA_Data *port[7];
    Coeff hp1, hp2, hp3, lp, sub1, sub2, body, partials;
    State state;
} Plugin;

enum Shape { LOW, HIGH, BAND };
static Coeff biquad(enum Shape shape, double frequency, double q) {
    double omega = 6.283185307179586 * frequency / 48000.;
    double c = cos(omega), alpha = sin(omega) / (2. * q);
    double b0 = alpha, b1 = 0., b2 = -alpha;
    if (shape == LOW) { b0 = b2 = .5 * (1. - c); b1 = 2. * b0; }
    if (shape == HIGH) { b0 = b2 = .5 * (1. + c); b1 = -2. * b0; }
    double norm = 1. / (1. + alpha);
    return (Coeff){ b0*norm, b1*norm, b2*norm, -2.*c*norm, (1.-alpha)*norm };
}
static double tick(Filter *z, const Coeff *c, double x) {
    double y = c->b0 * x + z->z1;
    z->z1 = c->b1 * x - c->a1 * y + z->z2;
    z->z2 = c->b2 * x - c->a2 * y;
    return y;
}
static double unit(double x) { return fmax(0., fmin(1., x)); }
static LADSPA_Handle create(const LADSPA_Descriptor *desc, unsigned long rate) {
    (void)desc;
    if (rate != 48000) return NULL;
    Plugin *p = calloc(1, sizeof(*p));
    if (p) {
        p->hp1 = biquad(HIGH, 160., .5176381);
        p->hp2 = biquad(HIGH, 160., .7071068);
        p->hp3 = biquad(HIGH, 160., 1.9318517);
        p->lp = biquad(LOW, 480., .7071068);
        p->sub1 = biquad(LOW, 95., .5411961);
        p->sub2 = biquad(LOW, 95., 1.306563);
        p->body = biquad(BAND, 225., 1.15);
        p->partials = biquad(BAND, 433., 1.38);
    }
    return p;
}
static void run(LADSPA_Handle h, unsigned long count) {
    Plugin *p = h;
    State *s = &p->state;
    const double amount=unit(*p->port[6]);
    for (unsigned long i=0; i<count; ++i) {
        double upper_power=0., sub_power=0., body[2];
        for (int ch=0; ch<2; ++ch) {
            Channel *v = &s->channels[ch];
            double x=p->port[ch][i];
            double upper=tick(&v->hp1, &p->hp1, x);
            upper=tick(&v->hp2, &p->hp2, upper);
            upper=tick(&v->hp3, &p->hp3, upper);
            upper=tick(&v->lp, &p->lp, upper);
            double sub=tick(&v->sub1, &p->sub1, x);
            sub=tick(&v->sub2, &p->sub2, sub);
            upper_power += .5 * upper * upper;
            sub_power += .5 * sub * sub;
            /* Emphasize upper partials already present in the recording.
               The smaller 225 Hz band retains body, while a little low bass
               is removed from this send to limit extra driver movement. */
            double dry = p->port[ch+2][i];
            v->low += .013 * (dry - v->low);
            double partials = tick(&v->partials, &p->partials, dry);
            body[ch] = partials + .36*tick(&v->body, &p->body, dry) - .19*v->low;
        }
        /* Linked 8 ms and 130 ms energy envelopes preserve stereo placement. */
        s->fast += .00260078 * (upper_power - s->fast);
        s->slow += .00016024 * (upper_power - s->slow);
        s->sub += .00260078 * (sub_power - s->sub);
        double proportion = s->fast / (s->fast + s->sub + 1e-12);
        double present = unit((proportion-.008)/.075) * s->fast/(s->fast+1e-9);
        double attack = unit((s->fast/(s->slow+1e-10)-1.05)/1.80);
        /* Keep the body lift for material with low bass beneath it. A short
           average prevents syllable edges from turning the gain on and off. */
        double fraction = s->sub/(s->sub+s->fast+1e-12);
        s->low_fraction += .0004*(fraction-s->low_fraction);
        double bass_present = unit((s->low_fraction-0.065)/0.14);
        /* Downstream compression does less work at quiet playback levels.
           Use less gain there to keep a quiet mix from becoming boomy. */
        s->key_power += .00042 * (upper_power + sub_power - s->key_power);
        double drive = unit((sqrt(s->key_power) - .019)/.068);
        /* Ease back on sustained, high-level bass. The 100 Hz square
           otherwise spends cone travel on its existing upper partials. */
        double hot = unit((s->key_power - .025)/.060);
        double mix = (.24 + .76*drive) * (1. - .82*hot);
        double target = amount * bass_present * present * mix * (1.3 + 1.1*attack);
        s->gain += .00260078 * (target-s->gain);
        for (int ch=0; ch<2; ++ch)
            p->port[4+ch][i] = (float)(s->gain * body[ch]);
    }
}
static void connect(LADSPA_Handle h, unsigned long port, LADSPA_Data *data) {
    ((Plugin *)h)->port[port]=data;
}
static void reset(LADSPA_Handle h) {
    Plugin *p=h;
    memset(&p->state, 0, sizeof(p->state));
}
#define IN (LADSPA_PORT_INPUT|LADSPA_PORT_AUDIO)
#define OUT (LADSPA_PORT_OUTPUT|LADSPA_PORT_AUDIO)
static const LADSPA_PortDescriptor ports[]={IN,IN,IN,IN,OUT,OUT,LADSPA_PORT_INPUT|LADSPA_PORT_CONTROL};
static const char *const names[]={"Key L","Key R","Body L","Body R","Add L","Add R","Amount"};
static const LADSPA_PortRangeHint hints[]={{0},{0},{0},{0},{0},{0},
    {LADSPA_HINT_BOUNDED_BELOW|LADSPA_HINT_BOUNDED_ABOVE|LADSPA_HINT_DEFAULT_0,0,1}};
static const LADSPA_Descriptor descriptor={
    .UniqueID=0x5d5705,.Label="programme_punch",.Name="Programme bass body and attacks",
    .Properties=LADSPA_PROPERTY_INPLACE_BROKEN,.Maker="speaker-dsp",.Copyright="None",
    .PortCount=7,.PortDescriptors=ports,.PortNames=names,.PortRangeHints=hints,
    .instantiate=create,.connect_port=connect,.activate=reset,.run=run,.cleanup=free
};
const LADSPA_Descriptor *music_descriptor(unsigned long index) { return index ? NULL : &descriptor; }
