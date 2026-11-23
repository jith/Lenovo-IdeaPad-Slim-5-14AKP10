/* A 48 kHz stereo-to-mono harmonic send for isolated low notes. Fit a sinusoid
 * to a 300 ms bass window every 10 ms, and fade out when that fit is ambiguous
 * or speech or music masks the note. All oscillator orders follow that pitch. */
#include <ladspa.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

enum { RATE=48000, HOP=480, WIN=180, BINS=753, ORDERS=26 };
static const double tau = 6.2831853071795864769;
/* scipy.signal.butter SOS, with the unit denominator coefficient omitted. */
static const double low_sos[][5] = {
    {.9987049983819032,-1.9974099967638064,.9987049983819032,-1.9974083197339119,.9974116737936998},
    {6.005792484924228e-14,1.2011584969848456e-13,6.005792484924228e-14,-1.9758593790295924,.9760153968985261},
    {1,2,1,-1.9822289297925284,.9823854506141251},
    {1,2,1,-1.9933590261623586,.9935164258389664}
};
static const double high_sos[][5] = {
    {.971343047066235,-1.94268609413247,.971343047066235,-1.9592282920296695,.9597134908873164},
    {1,-2,1,-1.982622534760675,.9831135271544272}
};
typedef struct {
    double low_state[4][2], high_state[2][2][2], low[WIN];
    double recent[50], high_rms[5], high_sum;
    int head, sample;
    double phase, step, amplitude, end_amp, weight[ORDERS], previous_weight[ORDERS];
    int have_weights, first_order, last_order;
} State;
typedef struct {
    LADSPA_Data *port[4];
    double cosine[BINS][WIN], sine[BINS][WIN], window[WIN];
    double cc[BINS], ss[BINS], cs[BINS], invdet[BINS];
    State state;
} Plugin;

static double clamp(double x) { return fmin(1., fmax(0., x)); }
static double filter(double x, const double co[][5], double z[][2], int n) {
    for (int i=0; i<n; ++i) {
        double y=co[i][0]*x+z[i][0];
        z[i][0]=co[i][1]*x-co[i][3]*y+z[i][1];
        z[i][1]=co[i][2]*x-co[i][4]*y;
        x=y;
    }
    return x;
}
static LADSPA_Handle create(const LADSPA_Descriptor *desc, unsigned long rate) {
    (void)desc;
    if (rate!=RATE) return NULL;
    Plugin *p=calloc(1,sizeof(*p));
    if (!p) return NULL;
    for (int j=0; j<WIN; ++j) {
        double edge=fmin(j,WIN-1-j)/(.175*(WIN-1));
        p->window[j]=(edge>=1) ? 1 : .5*(1-cos(.5*tau*edge));
    }
    for (int k=0; k<BINS; ++k) {
        double f=16+.125*k;
        for (int j=0; j<WIN; ++j) {
            double a=tau*f*(j-WIN)/600, c=cos(a), s=sin(a), w=p->window[j];
            p->cosine[k][j]=c; p->sine[k][j]=s;
            p->cc[k]+=w*c*c; p->ss[k]+=w*s*s; p->cs[k]+=w*c*s;
        }
        p->invdet[k]=1/(p->cc[k]*p->ss[k]-p->cs[k]*p->cs[k]);
    }
    return p;
}

static void next_hop(Plugin *p) {
    State *s=&p->state;
    double weighted[WIN], energy=0, recent=0;
    for (int j=0; j<WIN; ++j) {
        double x=s->low[(s->head+j)%WIN];
        weighted[j]=x*p->window[j]; energy+=weighted[j]*x;
        if (j>=WIN-12) recent=fmax(recent,fabs(x));
    }
    memmove(s->recent,s->recent+1,49*sizeof(double));
    s->recent[49]=recent;
    memmove(s->high_rms,s->high_rms+1,4*sizeof(double));
    s->high_rms[4]=sqrt(s->high_sum/HOP);
    s->high_sum=0;

    double best=0, best_u=0, best_v=0;
    int bin=0;
    if (energy>1e-16) {
        for (int k=0; k<BINS; ++k) {
            double c=0, v=0;
            #pragma omp simd reduction(+:c,v)
            for (int j=0; j<WIN; ++j) {
                c+=weighted[j]*p->cosine[k][j];
                v+=weighted[j]*p->sine[k][j];
            }
            double u=(c*p->ss[k]-v*p->cs[k])*p->invdet[k];
            double b=(v*p->cc[k]-c*p->cs[k])*p->invdet[k];
            double fit=u*c+b*v;
            if (fit>best) { best=fit; best_u=u; best_v=b; bin=k; }
        }
    }
    double hz=16+.125*bin, level=hypot(best_u,best_v);
    double taper=.5+.5*cos(.5*tau*clamp((hz-61)/28));
    double wanted=fmin(level,1.3*recent)*clamp(hz-24)*taper;
    wanted*=clamp((best/fmax(energy,1e-20)-.965)/.025)*clamp((level-.0007)/.0015);
    if (wanted>0) {
        double sorted[50], high=0;
        memcpy(sorted,s->recent,sizeof(sorted));
        for (int i=1; i<50; ++i) {
            double v=sorted[i]; int j=i;
            while (j>0 && sorted[j-1]>v) { sorted[j]=sorted[j-1]; --j; }
            sorted[j]=v;
        }
        double soft=sorted[3]+.92*(sorted[4]-sorted[3]);
        double loud=sorted[44]+.1*(sorted[45]-sorted[44]);
        for (int j=0; j<5; ++j) high=fmax(high,s->high_rms[j]);
        wanted*=clamp((soft/fmax(loud,1e-9)-.70)/.18);
        wanted*=clamp((.09-high/fmax(level/sqrt(2.),1e-9))/.06);
    }
    s->amplitude=s->end_amp;
    if (wanted==0 && s->amplitude<1e-8) {
        s->amplitude=s->end_amp=0;
        return;
    }
    s->end_amp=s->amplitude+(wanted-s->amplitude)*(wanted<s->amplitude?.45:.30);
    memcpy(s->previous_weight,s->weight,sizeof(s->weight));
    if (wanted>0) {
        double target=atan2(-best_v,best_u);
        if (s->amplitude==0) s->phase=target;
        double error=remainder(target-s->phase,tau);
        s->step=tau*hz/RATE+fmin(.12,fmax(-.12,error))/HOP;
        double sum=0;
        double centre=420+2.7*hz;
        for (int n=6;n<=31;++n) {
            double off=(n*hz-centre)/165, w=fmax(0,1-off*off);
            s->weight[n-6]=w*w; sum+=w*w*w*w;
        }
        double scale=1/sqrt(sum);
        for (int i=0;i<ORDERS;++i) s->weight[i]*=scale;
        if (!s->have_weights) {
            memcpy(s->previous_weight,s->weight,sizeof(s->weight));
            s->have_weights=1;
        }
    }
    s->first_order=32; s->last_order=5;
    for (int n=6;n<=31;++n) {
        if (s->weight[n-6]>0 || s->previous_weight[n-6]>0) {
            if (s->first_order>n) s->first_order=n;
            s->last_order=n;
        }
    }
}
static void run(LADSPA_Handle handle,unsigned long count) {
    Plugin *p=handle;
    State *s=&p->state;
    double gain=fmin(.055,fmax(0,*p->port[3]));
    for (unsigned long i=0;i<count;++i) {
        if (!s->sample) next_hop(p);
        double l=p->port[0][i], r=p->port[1][i];
        double low=filter((l+r)*.5,low_sos,s->low_state,4);
        if (s->sample%80==0) { s->low[s->head]=low; s->head=(s->head+1)%WIN; }
        double hl=filter(l,high_sos,s->high_state[0],2), hr=filter(r,high_sos,s->high_state[1],2);
        s->high_sum+=.5*(hl*hl+hr*hr);
        double wet=0;
        if (s->end_amp>0 || s->amplitude>0) {
            double phase=s->phase+s->sample*s->step, upper=0;
            double portion=(double)s->sample/HOP;
            for (int n=s->first_order;n<=s->last_order;++n) {
                double old=s->previous_weight[n-6], w=old+(s->weight[n-6]-old)*portion;
                upper+=w*cos(n*phase+1.18*n*n);
            }
            double env=s->amplitude+(s->end_amp-s->amplitude)*portion;
            wet=env*(.76*upper+.38*cos(3*phase)+.36*cos(5*phase));
        }
        p->port[2][i]=(float)(gain*wet);
        if (++s->sample==HOP) {
            if (s->end_amp>0 || s->amplitude>0) s->phase=fmod(s->phase+HOP*s->step,tau);
            s->sample=0;
        }
    }
}
static void reset(LADSPA_Handle h) { Plugin *p=h; memset(&p->state,0,sizeof(p->state)); }
static void connect_port(LADSPA_Handle h,unsigned long port,LADSPA_Data *data) {
    Plugin *p=h; p->port[port]=data;
}
static const LADSPA_PortDescriptor ports[]={
    LADSPA_PORT_INPUT|LADSPA_PORT_AUDIO, LADSPA_PORT_INPUT|LADSPA_PORT_AUDIO,
    LADSPA_PORT_OUTPUT|LADSPA_PORT_AUDIO, LADSPA_PORT_INPUT|LADSPA_PORT_CONTROL
};
static const char *const names[]={"Left","Right","Cue","Strength"};
static const LADSPA_PortRangeHint hints[]={{0,0,0},{0,0,0},{0,0,0},
    {LADSPA_HINT_BOUNDED_BELOW|LADSPA_HINT_BOUNDED_ABOVE|LADSPA_HINT_DEFAULT_0,0,.055f}};
static const LADSPA_Descriptor descriptor={
    .UniqueID=0x5d5702,.Label="sustained_bass",.Name="Sustained bass harmonic send",
    .Maker="speaker-dsp",.Copyright="None",.PortCount=4,.PortDescriptors=ports,.PortNames=names,
    .PortRangeHints=hints,.instantiate=create,.connect_port=connect_port,.activate=reset,.run=run,.cleanup=free
};
const LADSPA_Descriptor *smooth_descriptor(unsigned long index) { return index==0?&descriptor:NULL; }
