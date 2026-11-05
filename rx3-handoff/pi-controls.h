/* RX3_TOP_BUTTONS_V3: trial, reversible */
/* RX3_TOP_BUTTONS_V1: trial, reversible */
#ifndef PI_CONTROLS_H
#define PI_CONTROLS_H
/* Shared geometry and controls for the presenter (fb-present.c) and the touch bridge (touch-bridge.c).
   7-inch layout: the complete 1280x800 firmware picture fills the area below
   six top-row buttons on the original 800x480 Raspberry Pi display.
   Everything else (deck faders, master/headphone levels, crossfader, cue buttons, browse/load/play keys)
   lives on the DDJ-FLX4 or on the firmware's own touch UI. */
/* Override at build time: gcc -DRX3_ROOT_PATH='"/home/you/rx3-rootfs"' ... (install.sh does this). */
#ifndef RX3_ROOT_PATH
#define RX3_ROOT_PATH "/home/rx3/rx3-rootfs"
#endif
#define UI_STATE RX3_ROOT_PATH "/dev/rx3-ui-state"
#define UI_CONTROL RX3_ROOT_PATH "/dev/rx3-control"
#define FW_W 1280
#define FW_H 800
struct command {int key,operation,channel,value;float analog;int extra;};
/* level[] and headphone_cue are unused since the on-screen mixer went; kept so the state file layout is unchanged. */
struct ui_state {unsigned magic;float level[6];unsigned pressed;unsigned headphone_cue;int cursor_x,cursor_y,cursor_visible;unsigned shutdown_show,shutdown_progress;};
struct button {const char *label,*sub;int key,channel;unsigned color;};
#define NBUTTONS 6
static const struct button buttons[NBUTTONS]={
 {"SOURCE",0,0x201,0,0x08699c},
 {"BROWSE",0,0x202,0,0x08699c},
 {"USB1",0,0x8002,1,0x7a2f2f},
 {"USB2",0,0x8002,2,0x7a2f2f},
 {"SEARCH",0,-1,0,0x08699c},
 {"POWER",0,-2,0,0x08699c}
};
/* RX3 top-row v3: full-width display with independent horizontal/vertical
   scaling. Keep the entire 1280x800 firmware frame visible without cropping.
   7-inch aspect ratio differs from firmware so FIT-to-area stretches modestly. */
struct layout {int W,H,rot,LW,LH,col,cx,cy,cw,ch;double s,sx,sy;struct {int x,y,w,h;} btn[NBUTTONS],status;};
static struct layout make_layout(int W,int H,int rot){
 struct layout L;L.W=W;L.H=H;L.rot=rot;
 int sideways=rot==90||rot==270;L.LW=sideways?H:W;L.LH=sideways?W:H;
 L.col=L.LW/10;
 /* Shorter, more hardware-like button rail. */
 int top=L.LH/12;if(top<42)top=42;if(top>70)top=70;
 int margin=L.LW/68;if(margin<6)margin=6;
 int gap=L.LW/120;if(gap<4)gap=4;
 int bw=(L.LW-2*margin-5*gap)/NBUTTONS;
 int bh=top*68/100;if(bh<25)bh=25;
 for(int i=0;i<NBUTTONS;i++){
  L.btn[i].x=margin+i*(bw+gap);L.btn[i].y=(top-bh)/2;
  L.btn[i].w=bw;L.btn[i].h=bh;
 }
 /* Fill available viewport, preserving all edges and all screen content. */
 int xmargin=L.LW/120;if(xmargin<3)xmargin=3;
 int bottom=L.LH/140;if(bottom<3)bottom=3;
 L.cx=xmargin;L.cy=top;
 L.cw=L.LW-2*xmargin;L.ch=L.LH-top-bottom;
 L.sx=(double)L.cw/FW_W;L.sy=(double)L.ch/FW_H;
 L.s=L.sx; /* only for existing diagnostics; sampling uses sx / sy */
 L.status.x=0;L.status.y=L.LH+10;L.status.w=0;L.status.h=0;
 return L;
}
/* Panel pixel -> logical pixel (rotation only; the canvas covers the whole panel). */
static inline void panel_to_logical(const struct layout*L,int px,int py,int*lx,int*ly){
 switch(L->rot){case 90:*lx=py;*ly=L->LH-1-px;break;case 180:*lx=L->LW-1-px;*ly=L->LH-1-py;break;case 270:*lx=L->LW-1-py;*ly=px;break;default:*lx=px;*ly=py;}}
static int button_at(const struct layout*L,int lx,int ly){
 for(int i=0;i<NBUTTONS;i++)if(lx>=L->btn[i].x&&lx<L->btn[i].x+L->btn[i].w&&ly>=L->btn[i].y&&ly<L->btn[i].y+L->btn[i].h)return i;return -1;}
/* SOURCE-screen shutdown test overlay. Firmware coordinates keep its location
   consistent with every existing panel size and rotation. */
#define RX3_POWER_X 805
#define RX3_POWER_Y 608
#define RX3_POWER_W 365
#define RX3_POWER_H 59
#define RX3_POWER_HOLD_MS 3000
/* v3: SOURCE page fingerprint obtained from *read-only numeric* measurements
   on the real Pi 4 (firmware 1.19, native 1280 x 800 BGRX framebuffer).
   SOURCE stays constant while idle. Navigating with FLX4 changes the title
   and removes the MY SETTINGS caption. Check BOTH regions independently.
   On any unexpected screen or missing framebuffer, fail closed (no button).
   Detection is entirely host-side; no Pioneer firmware code is changed. */
static int rx3_source_screen_visible(const unsigned char *fb){
 if(!fb)return 0;
 int head=0,settings=0;
 for(int y=30;y<88;y+=2)for(int x=12;x<188;x+=2){
  const unsigned char *p=fb+((size_t)y*FW_W+x)*4;
  head+=(p[0]>140&&p[1]>140&&p[2]>110);
 }
 for(int y=510;y<620;y+=4)for(int x=745;x<1255;x+=4){
  const unsigned char *p=fb+((size_t)y*FW_W+x)*4;
  settings+=(p[0]>140&&p[1]>140&&p[2]>110);
 }
 /* Measured SOURCE 105 / 112; hardware BROWSE 187 / 0.
    Use tolerance for slight rendering differences, never a match solely
    on the title or an arbitrary "learned" screen. */
 return head>=70&&head<=150&&settings>=70&&settings<=175;
}
static void power_rect(const struct layout *L,int *x,int *y,int *w,int *h){
 *x=L->cx+(int)(RX3_POWER_X*L->s);*y=L->cy+(int)(RX3_POWER_Y*L->s);
 *w=(int)(RX3_POWER_W*L->s);*h=(int)(RX3_POWER_H*L->s);
}
static int power_at(const struct layout *L,int lx,int ly){
 int x,y,w,h;power_rect(L,&x,&y,&w,&h);
 return lx>=x&&lx<x+w&&ly>=y&&ly<y+h;
}
/* RX3_ROTATE picks the rotation (0/90/180/270, clockwise); otherwise portrait panels get 90, landscape 0. */
static int rotation_for(int W,int H){const char*e=getenv("RX3_ROTATE");
 if(e&&*e){int r=atoi(e);if(r==0||r==90||r==180||r==270)return r;fprintf(stderr,"RX3_ROTATE=%s ignored: use 0, 90, 180 or 270\n",e);}
 return H>W?90:0;}
/* RX3_FB names the framebuffer to draw on (rx3-env.sh picks the DSI panel when one exists). */
static const char *fb_device(void){const char*e=getenv("RX3_FB");return e&&*e?e:"/dev/fb0";}
#endif
