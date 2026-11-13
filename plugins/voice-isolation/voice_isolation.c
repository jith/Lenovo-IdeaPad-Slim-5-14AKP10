/* Voice Isolation: keep the voice, silence everything else. No neural network.
 *
 * A LADSPA plugin for the built-in microphone's two capsules, mono out, loaded by the PipeWire
 * filter-chain process from /etc/pipewire/filter-chain.conf.d/57-voice-isolation.conf.
 * Built by install.sh; see README, "Voice Isolation".
 *
 * Per 21 ms frame (1024 points, hop 256, 48 kHz):
 *
 *   noise tracking   unbiased MMSE estimate driven by speech-presence
 *                    probability (Gerkmann & Hendriks, 2012): each bin follows
 *                    the noise whenever speech is improbable there, within a
 *                    few frames. Steady noise -- this room's 160-240 Hz hum --
 *                    is learned and followed as it changes. An earlier
 *                    minimum-statistics tracker read the noise 2.6x low here,
 *                    so the hum survived into the voice detector.
 *   gain             OM-LSA: log-spectral amplitude gain from decision-directed
 *                    a priori SNR, weighted by the probability that each bin
 *                    holds speech, down to a floor.
 *   voice detection  YIN pitch on a 300 Hz - 1.5 kHz copy decimated to 8 kHz,
 *                    AND the 300 Hz - 3.5 kHz level over its own floor AND over
 *                    an absolute level AND the two capsules agreeing (1-4 kHz
 *                    coherence). The last two are what tell the speaker at the
 *                    laptop from people talking elsewhere in the house: on the
 *                    user's own recordings, 24 Sep 2026, far voices were as
 *                    voiced as theirs but quieter and less coherent. Spectral pitch measures failed here: the hum is
 *                    a few loud steady tones, which every power-domain measure
 *                    calls periodic, and 47 Hz bins cannot resolve a low
 *                    voice's harmonics. Voiced frames open a speech region
 *                    that holds 250 ms after the voice stops, so the consonants
 *                    around vowels survive; 32 ms of lookahead opens it before
 *                    the first voiced frame, so onsets survive too.
 *   silence          outside a speech region every bin is presumed noise, and
 *                    a gate takes the frame down to the silence depth.
 *
 * Latency is one frame plus the lookahead, 1024 + 6 * 256 = 2560 samples, 53 ms,
 * reported on the "latency" port. Real-time safe: nothing is allocated, locked or logged in
 * run(). Learned noise survives activate(), so each recording does not start
 * by relearning the room.
 *
 * No high-pass. An 80 Hz one was here and cost 10 dB of SI-SDR on clean speech
 * by itself: it shifts the phase of a low voice's fundamental. The noise tracker
 * takes steady rumble out anyway.
 *
 * Build with -DVI_TRACE to print each frame's voice decision on stderr.
 */

#include <ladspa.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#ifdef VI_TRACE
#include <stdio.h>
#endif
#if defined(__SSE__)
#include <xmmintrin.h>
#endif

#define N 1024                 /* frame */
#define H 256                  /* hop */
#define K (N / 2 + 1)          /* bins */
#define LOOK 6                 /* lookahead, frames */
#define RING (LOOK + 1)
#define LATENCY (N + LOOK * H)
#define DEC 6                  /* 48 kHz -> 8 kHz for the pitch tracker */
#define YW 256                 /* YIN window, 32 ms at 8 kHz */
#define YT0 20                 /* shortest period, 400 Hz */
#define YT1 100                /* longest period, 80 Hz */
#define YRING 512
#define FLOOR_MIN_DB (-60.f)   /* band power of a frame at about -100 dBFS */
/* Chosen jointly on the user's own takes (their voice near, other people's
 * far) and on stereo synthetic scenes built from this room's two-capsule noise,
 * 24 Sep 2026: their speech kept open 94.6% of the time; far voices opened
 * 2.1%; pauses opened 0% in the room, 8% under keyboard clicks, 29% under music.
 *
 * A keyboard click is loud, near and coherent, so only duration tells it from
 * a voice: VOICED_RUN frames in a row. Without it, the pitch bar low enough to
 * catch the user's real voice (0.4) opened 81% of the keyboard pauses.
 *
 * The first thresholds (0.82, 26 dB over the floor) came from espeak speech at
 * -30 dBFS, 12-15 dB louder than a real voice at this mic: on the real voice
 * they fired on 1% of frames and gated the speaker out. */
#ifndef VOICED_PITCH
#define VOICED_PITCH 0.7f      /* YIN periodicity, 1 - aperiodicity */
#endif
#ifndef VOICED_FLOOR_DB
#define VOICED_FLOOR_DB 4.f    /* 300 Hz - 3.5 kHz level over its floor */
#endif
#ifndef VOICED_LEVEL_DB
#define VOICED_LEVEL_DB 2.f    /* the same level, absolute; Reach lowers it */
#endif
#ifndef VOICED_COHERENCE
#define VOICED_COHERENCE 0.4f  /* 1-4 kHz coherence between the capsules */
#endif
#ifndef VOICED_RUN
#define VOICED_RUN 6           /* frames in a row, 32 ms: longer than a click */
#endif
#if VOICED_RUN > RING
#error "a run is marked back through the lookahead ring, so it cannot be longer"
#endif

enum { P_IN_L, P_IN_R, P_OUT, P_STRENGTH, P_DEPTH, P_REACH, P_BYPASS, P_LATENCY, P_COUNT };

typedef struct { float re, im; } cpx;

typedef struct {
    LADSPA_Data *port[P_COUNT];
    float fs, bin_hz;

    cpx tw[N / 2];
    int rev[N];
    float win[N];

    float inql[N], inqr[N], outq[H], ola[N];
    int rover;

    int started;
    float noise[K], pbar[K], g1prev[K], gamprev[K];
    cpx sxy[K];
    float sxx[K], syy[K];
    float floor_db;
    int floor_db_set;

    float bq[4][5], bz[4][2];  /* 300 Hz high-pass x2, 1.5 kHz low-pass x2 */
    float yring[YRING];
    int ypos, yphase;

    cpx X[RING][K];
    float G1[RING][K], xi[RING][K], vv[RING][K];
    int voiced[RING];

    long frame;
    int run, hang, hang_frames;
    float gate, gate_rel;

    cpx buf[N];
} VI;

static float clampf(float x, float lo, float hi) { return x < lo ? lo : x > hi ? hi : x; }

static void fft(const VI *s, cpx *a, int inverse)
{
    for (int i = 0; i < N; i++) {
        int j = s->rev[i];
        if (i < j) { cpx t = a[i]; a[i] = a[j]; a[j] = t; }
    }
    for (int len = 2; len <= N; len <<= 1) {
        int half = len >> 1, step = N / len;
        for (int i = 0; i < N; i += len)
            for (int k = 0; k < half; k++) {
                cpx w = s->tw[k * step];
                if (inverse) w.im = -w.im;
                cpx u = a[i + k], v = a[i + k + half];
                cpx t = { v.re * w.re - v.im * w.im, v.re * w.im + v.im * w.re };
                a[i + k] = (cpx){ u.re + t.re, u.im + t.im };
                a[i + k + half] = (cpx){ u.re - t.re, u.im - t.im };
            }
    }
}

/* Exponential integral E1, for the log-spectral amplitude gain. */
static float e1(float x)
{
    if (x < 1e-8f) x = 1e-8f;
    if (x < 1.f)
        return -0.5772157f - logf(x) + x - x * x * 0.25f + x * x * x / 18.f
               - x * x * x * x / 96.f;
    if (x > 40.f) return 0.f;
    return (x * x + 2.334733f * x + 0.250621f) / (x * x + 3.330657f * x + 1.681534f)
           * expf(-x) / x;
}

static void reset_stream(VI *s)
{
    memset(s->inql, 0, sizeof s->inql);
    memset(s->inqr, 0, sizeof s->inqr);
    memset(s->outq, 0, sizeof s->outq);
    memset(s->ola, 0, sizeof s->ola);
    s->rover = N - H;
    memset(s->voiced, 0, sizeof s->voiced);
    memset(s->bz, 0, sizeof s->bz);
    memset(s->yring, 0, sizeof s->yring);
    s->ypos = s->yphase = 0;
    s->frame = 0;
    s->hang = 0;
    s->run = 0;
    s->gate = 0.f;
}

static LADSPA_Handle instantiate(const LADSPA_Descriptor *d, unsigned long rate)
{
    (void)d;
    VI *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    s->fs = (float)rate;
    s->bin_hz = s->fs / N;

    for (int k = 0; k < N / 2; k++) {
        double a = -2.0 * M_PI * k / N;
        s->tw[k] = (cpx){ (float)cos(a), (float)sin(a) };
    }
    for (int i = 0; i < N; i++) {
        int r = 0;
        for (int b = 0; b < 10; b++) if (i & (1 << b)) r |= 1 << (9 - b);
        s->rev[i] = r;
    }
    for (int n = 0; n < N; n++)
        s->win[n] = (float)sqrt(0.5 - 0.5 * cos(2.0 * M_PI * n / N));
    for (int i = 0; i < 4; i++) {
        int hp = i < 2;
        double w = 2.0 * M_PI * (hp ? 300.0 : 1500.0) / s->fs;
        double c = cos(w), al = sin(w) / (2.0 * M_SQRT1_2), a0 = 1.0 + al;
        double b0 = (hp ? (1.0 + c) : (1.0 - c)) / 2.0;
        s->bq[i][0] = (float)(b0 / a0);
        s->bq[i][1] = (float)((hp ? -(1.0 + c) : (1.0 - c)) / a0);
        s->bq[i][2] = (float)(b0 / a0);
        s->bq[i][3] = (float)(-2.0 * c / a0);
        s->bq[i][4] = (float)((1.0 - al) / a0);
    }
    s->hang_frames = (int)(0.25f * s->fs / H);
    s->gate_rel = expf(-(float)H / (0.12f * s->fs));
    reset_stream(s);
    return s;
}

static void connect_port(LADSPA_Handle h, unsigned long p, LADSPA_Data *data)
{
    if (p < P_COUNT) ((VI *)h)->port[p] = data;
}

static void activate(LADSPA_Handle h) { reset_stream((VI *)h); }

static void process_frame(VI *s)
{
    const float strength = clampf(*s->port[P_STRENGTH], 0.f, 1.f);
    const float depth = clampf(*s->port[P_DEPTH], 0.f, 80.f);
    const float reach = clampf(*s->port[P_REACH], -12.f, 24.f);
    const int bypass = *s->port[P_BYPASS] > 0.5f;
    const int slot = (int)(s->frame % RING);
    float P[K];
    cpx XL[K];

    /* --- analysis: each capsule, and their mono mix --------------------- */
    for (int n = 0; n < N; n++) s->buf[n] = (cpx){ s->inql[n] * s->win[n], 0.f };
    fft(s, s->buf, 0);
    memcpy(XL, s->buf, sizeof XL);
    for (int n = 0; n < N; n++) s->buf[n] = (cpx){ s->inqr[n] * s->win[n], 0.f };
    fft(s, s->buf, 0);
    /* Capsule coherence, 1-4 kHz, cross-spectra smoothed over about 32 ms. */
    const int kc0 = (int)(1000.f / s->bin_hz), kc1 = (int)(4000.f / s->bin_hz);
    float coh = 0.f;
    for (int k = kc0; k <= kc1; k++) {
        cpx l = XL[k], r = s->buf[k];
        s->sxy[k].re = 0.85f * s->sxy[k].re + 0.15f * (l.re * r.re + l.im * r.im);
        s->sxy[k].im = 0.85f * s->sxy[k].im + 0.15f * (l.im * r.re - l.re * r.im);
        s->sxx[k] = 0.85f * s->sxx[k] + 0.15f * (l.re * l.re + l.im * l.im);
        s->syy[k] = 0.85f * s->syy[k] + 0.15f * (r.re * r.re + r.im * r.im);
        coh += (s->sxy[k].re * s->sxy[k].re + s->sxy[k].im * s->sxy[k].im)
               / (s->sxx[k] * s->syy[k] + 1e-30f);
    }
    coh /= (float)(kc1 - kc0 + 1);
    for (int k = 0; k < K; k++) {
        cpx m = { 0.5f * (XL[k].re + s->buf[k].re), 0.5f * (XL[k].im + s->buf[k].im) };
        s->X[slot][k] = m;
        P[k] = m.re * m.re + m.im * m.im + 1e-20f;
    }

    /* --- noise tracking: SPP-driven MMSE estimate ---------------------- */
    if (!s->started) {
        for (int k = 0; k < K; k++) {
            s->noise[k] = P[k];
            s->pbar[k] = 0.f;
            s->g1prev[k] = 1.f;
            s->gamprev[k] = 1.f;
        }
        s->started = 1;
    }
    const float xi_h1 = 31.62f;          /* speech assumed 15 dB up when present */
    const float over = 1.f + 0.5f * strength;
    float sig_band = 0.f;
    const int kb0 = (int)(300.f / s->bin_hz), kb1 = (int)(3500.f / s->bin_hz);
    for (int k = 0; k < K; k++) {
        float ph1 = 1.f / (1.f + (1.f + xi_h1)
                                 * expf(-fminf(P[k] / s->noise[k] * xi_h1 / (1.f + xi_h1), 80.f)));
        s->pbar[k] = 0.9f * s->pbar[k] + 0.1f * ph1;
        if (s->pbar[k] > 0.99f) ph1 = fminf(ph1, 0.99f);   /* never stop following */
        float en = (1.f - ph1) * P[k] + ph1 * s->noise[k];
        s->noise[k] = 0.86f * s->noise[k] + 0.14f * en + 1e-20f;

        /* --- gain (OM-LSA), the part that does not depend on voicing --- */
        float noise = over * s->noise[k];
        float gamma = fminf(P[k] / noise, 1e4f);
        float xi = 0.98f * s->g1prev[k] * s->g1prev[k] * s->gamprev[k]
                   + 0.02f * fmaxf(gamma - 1.f, 0.f);
        xi = fmaxf(xi, 0.003f);
        float v = gamma * xi / (1.f + xi);
        float g1 = fminf(xi / (1.f + xi) * expf(0.5f * e1(v)), 1.f);
        s->G1[slot][k] = g1;
        s->xi[slot][k] = xi;
        s->vv[slot][k] = v;
        s->g1prev[k] = g1;
        s->gamprev[k] = gamma;
        if (k >= kb0 && k <= kb1) sig_band += P[k];
    }

    /* --- voice detection: YIN periodicity and level over floor -------- */
    float seg[YW + YT1], cm[YT1 + 1];
    for (int j = 0; j < YW + YT1; j++)
        seg[j] = s->yring[(s->ypos - (YW + YT1) + j + YRING) & (YRING - 1)];
    float run_sum = 0.f, ap = 1.f;
    int tau = 0;
    for (int t = 1; t <= YT1; t++) {
        float acc = 0.f;
        for (int j = 0; j < YW; j++) { float df = seg[j] - seg[j + t]; acc += df * df; }
        run_sum += acc;
        cm[t] = run_sum > 1e-20f ? acc * t / run_sum : 1.f;
    }
    for (int t = YT0; t <= YT1; t++)          /* first clear dip, else the deepest */
        if (cm[t] < 0.15f && (t == YT1 || cm[t] <= cm[t + 1])) { tau = t; break; }
    if (!tau)
        for (int t = YT0; t <= YT1; t++) if (!tau || cm[t] < cm[tau]) tau = t;
    ap = cm[tau];
    /* The level floor falls at once and rises 1 dB/s. It is not touched until
     * a whole frame of real input is in -- the first frames after a reset are
     * mostly zeros, and a floor that low took a minute to climb back, opening
     * the gate on everything periodic meanwhile -- and it never goes below
     * FLOOR_MIN_DB, which a muted mic would otherwise drag it to. */
    const float band_db = fmaxf(10.f * log10f(sig_band + 1e-20f), FLOOR_MIN_DB);
    const int settled = s->frame >= N / H;
    if (settled) {
        if (!s->floor_db_set) { s->floor_db = band_db; s->floor_db_set = 1; }
        s->floor_db = fminf(band_db, s->floor_db + (float)H / s->fs);
    }
    const float voicing = 1.f - ap, over_floor = band_db - s->floor_db;
    const int cand = settled && voicing > VOICED_PITCH && over_floor > VOICED_FLOOR_DB
                     && band_db > VOICED_LEVEL_DB - reach && coh > VOICED_COHERENCE;
    s->run = cand ? s->run + 1 : 0;
    s->voiced[slot] = 0;
    if (s->run == VOICED_RUN)          /* the whole run counts, back to its start */
        for (int j = 0; j < VOICED_RUN; j++) s->voiced[(slot - j + RING) % RING] = 1;
    else if (s->run > VOICED_RUN)
        s->voiced[slot] = 1;
#ifdef VI_TRACE
    fprintf(stderr, "F %ld %.3f %.1f %d %d %.2f %.3f\n", s->frame, voicing, over_floor,
            s->voiced[slot], tau, band_db, coh);
#endif

    const long m = s->frame++;
    if (m < LOOK) return;       /* the ring is still filling: output stays silent */

    /* --- decide for the frame leaving the lookahead window ------------- */
    const int o = (int)((m - LOOK) % RING);
    int ahead = 0;
    for (int j = 0; j <= LOOK; j++) ahead |= s->voiced[(o + j) % RING];
    if (s->voiced[o]) s->hang = s->hang_frames;
    const int region = ahead || s->hang > 0;
    if (s->hang > 0) s->hang--;

    const float target = region ? 1.f : powf(10.f, -depth / 20.f);
    s->gate = target > s->gate ? target : s->gate_rel * s->gate + (1.f - s->gate_rel) * target;

    /* Strength is how much of the noise UNDER the voice goes: the spectral
     * gain is mixed in from none at 0 to all of it, down to -20 dB, at 1.
     * Pauses are the gate's, whatever the strength. */
    const float gmin = powf(10.f, -20.f / 20.f);
    const float q_out = 0.5f + 0.49f * strength;

    for (int k = 0; k < K; k++) {
        float g = 1.f;
        if (!bypass) {
            float q = region ? 0.25f : q_out;
            float xi = s->xi[o][k], v = s->vv[o][k];
            float p = 1.f / (1.f + q / (1.f - q) * (1.f + xi) * expf(-fminf(v, 80.f)));
            float gs = powf(s->G1[o][k], p) * powf(gmin, 1.f - p);
            g = (1.f - strength + strength * gs) * s->gate;
        }
        s->buf[k] = (cpx){ s->X[o][k].re * g, s->X[o][k].im * g };
        if (k > 0 && k < N / 2) s->buf[N - k] = (cpx){ s->buf[k].re, -s->buf[k].im };
    }
    fft(s, s->buf, 1);
    /* sqrt-Hann in and out at 75% overlap sums to 2; with the 1/N of the
     * inverse transform that is H / (N/2) / N. */
    const float scale = (float)H / (N / 2) / N;
    for (int n = 0; n < N; n++) s->ola[n] += s->buf[n].re * s->win[n] * scale;
}

static void run(LADSPA_Handle h, unsigned long count)
{
    VI *s = (VI *)h;
#if defined(__SSE__)
    unsigned csr = _mm_getcsr();
    _mm_setcsr(csr | 0x8040);   /* flush denormals: silence must not cost CPU */
#endif
    const LADSPA_Data *inl = s->port[P_IN_L], *inr = s->port[P_IN_R];
    LADSPA_Data *out = s->port[P_OUT];
    if (s->port[P_LATENCY]) *s->port[P_LATENCY] = LATENCY;

    for (unsigned long i = 0; i < count; i++) {
        float y = 0.5f * (inl[i] + inr[i]);
        for (int b = 0; b < 4; b++) {          /* transposed direct form II */
            float *q = s->bq[b], *z = s->bz[b];
            float o = q[0] * y + z[0];
            z[0] = q[1] * y - q[3] * o + z[1];
            z[1] = q[2] * y - q[4] * o;
            y = o;
        }
        if (++s->yphase == DEC) {
            s->yphase = 0;
            s->yring[s->ypos] = y;
            s->ypos = (s->ypos + 1) & (YRING - 1);
        }
        s->inql[s->rover] = inl[i];
        s->inqr[s->rover] = inr[i];
        out[i] = s->outq[s->rover - (N - H)];
        if (++s->rover >= N) {
            s->rover = N - H;
            process_frame(s);
            memcpy(s->outq, s->ola, sizeof s->outq);
            memmove(s->ola, s->ola + H, (N - H) * sizeof(float));
            memset(s->ola + N - H, 0, H * sizeof(float));
            memmove(s->inql, s->inql + H, (N - H) * sizeof(float));
            memmove(s->inqr, s->inqr + H, (N - H) * sizeof(float));
        }
    }
#if defined(__SSE__)
    _mm_setcsr(csr);
#endif
}

static void cleanup(LADSPA_Handle h) { free(h); }

static const LADSPA_PortDescriptor port_desc[P_COUNT] = {
    LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO,
    LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO,
    LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO,
    LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
    LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
    LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
    LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
    LADSPA_PORT_OUTPUT | LADSPA_PORT_CONTROL,
};

static const char *const port_names[P_COUNT] = {
    "In L", "In R", "Out", "Strength", "Silence depth (dB)", "Reach (dB)", "Bypass", "latency",
};

static const LADSPA_PortRangeHint port_hints[P_COUNT] = {
    { 0, 0, 0 },
    { 0, 0, 0 },
    { 0, 0, 0 },
    { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_MAXIMUM, 0.f, 1.f },
    { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_HIGH, 0.f, 80.f },
    /* Reach: how much quieter than the default a voice may be and still count
     * as the speaker's. Raise it if sitting farther back cuts you out. */
    { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_0, -12.f, 24.f },
    { LADSPA_HINT_TOGGLED | LADSPA_HINT_DEFAULT_0, 0.f, 1.f },
    { 0, 0, 0 },
};

static const LADSPA_Descriptor descriptor = {
    .UniqueID = 0x5d5701,
    .Label = "voice_isolation",
    .Properties = LADSPA_PROPERTY_HARD_RT_CAPABLE,
    .Name = "speaker-dsp Voice Isolation",
    .Maker = "speaker-dsp",
    .Copyright = "None",
    .PortCount = P_COUNT,
    .PortDescriptors = port_desc,
    .PortNames = port_names,
    .PortRangeHints = port_hints,
    .instantiate = instantiate,
    .connect_port = connect_port,
    .activate = activate,
    .run = run,
    .cleanup = cleanup,
};

const LADSPA_Descriptor *ladspa_descriptor(unsigned long index)
{
    return index == 0 ? &descriptor : NULL;
}
