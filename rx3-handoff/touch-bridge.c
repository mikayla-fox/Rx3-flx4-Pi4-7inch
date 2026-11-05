/* RX3_TOP_BUTTONS_V3: trial, reversible */
/* RX3_TOP_BUTTONS_V1: trial, reversible */
/* rx3-touch-bridge: turn touchscreen (or mouse, or replayed) input into RX3 firmware touch reports and sidebar
   button presses, using the same layout as the presenter. usage: rx3-touch-bridge [--mouse] <event device> <touch fifo>
   or rx3-touch-bridge --replay <touch fifo> with evdev events on stdin in firmware coordinates (1280x800). */
#include <linux/input.h>
#include <linux/fb.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <poll.h>
#include <time.h>
#include "pi-controls.h"
struct __attribute__((packed)) report {uint8_t down,pad;uint16_t x,y;};
struct finger {int x,y,down,active,region,escalated;long down_at;};
static int control;
static struct ui_state *state;
static long millis(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1000+t.tv_nsec/1000000;}
#define SHORTCUT_HOLD_MS 2000
/* The hold is processed locally; never forward this touch to Pioneer firmware. */
/* v3: Always check firmware page using independent known SOURCE
   header AND MY SETTINGS glyph counts, rather than learning whichever
   page happened to be visible after SOURCE was pressed. */
static const unsigned char *source_fb=0;
static int open_source_fb(void){
 int fd=open(RX3_ROOT_PATH "/dev/fb0",O_RDONLY);
 if(fd<0)return 0;
 struct stat st;
 if(fstat(fd,&st)!=0||st.st_size<(off_t)FW_W*FW_H*4){close(fd);return 0;}
 void *mapped=mmap(0,(size_t)FW_W*FW_H*4,PROT_READ,MAP_SHARED,fd,0);
 close(fd);
 if(mapped==MAP_FAILED)return 0;
 source_fb=(const unsigned char *)mapped;
 return 1;
}
static int request_poweroff(void){
 int fd=open(RX3_ROOT_PATH "/dev/rx3-priv",O_WRONLY|O_NONBLOCK);
 if(fd<0){perror("open shutdown helper");return 0;}
 const char *msg="poweroff\n";
 int ok=(write(fd,msg,strlen(msg))==(ssize_t)strlen(msg));
 if(!ok)perror("write shutdown helper");
 close(fd);return ok;
}

static int key_index(int key){for(int i=0;i<NBUTTONS;i++)if(buttons[i].key==key)return i;return -1;}
static void command(int key,int op,int ch,int value,float a){struct command c={key,op,ch,value,a,0};if(write(control,&c,sizeof(c))!=sizeof(c))perror("control");}
/* USB STOP (0x8002) is a plain press/release: the firmware times the hold itself (ejects ~1.9 s after press, an earlier
   release cancels). Never send its code 1 "long-pressed" event without a press: that poisons the slot until tapped. */
static void button(int i,int down){const struct button*b=&buttons[i];if(down)state->pressed|=1u<<i;else state->pressed&=~(1u<<i);command(b->key,down?0:2,b->channel,0,0);}
/* On-screen BROWSE: the press is only sent once we know it was a tap (released within 2 s), so a hold never
   also flips the screen. BROWSE goes library -> deck, and from any other screen -> library. */
static void browse_tap(void){command(0x202,0,0,0,0);command(0x202,2,0,0,0);}
/* On-screen BROWSE button, held 2 s: opens the SHORTCUT settings screen (LCD/jog brightness, vinyl speed adjust,
   waveform colour, quantize, headphone mono/split, fader curve ...) instead of the plain browse tap. */
static void shortcut_open(void){command(0x210,0,0,0,0);command(0x210,2,0,0,0);}
int main(int argc,char**argv){
 if(argc<3)return 2;
 int replay=!strcmp(argv[1],"--replay"),mouse=!strcmp(argv[1],"--mouse");if(mouse){if(argc<4)return 2;argv++;}
 int in=replay?0:open(argv[1],O_RDONLY),out=open(argv[2],O_RDWR|O_NONBLOCK);control=open(UI_CONTROL,O_RDWR|O_NONBLOCK);
 if(in<0||out<0||control<0){perror("open");return 1;}
 int sf=open(UI_STATE,O_RDWR|O_CREAT,0600);if(sf<0||ftruncate(sf,sizeof(struct ui_state)))return 1;
 state=mmap(0,sizeof(*state),PROT_READ|PROT_WRITE,MAP_SHARED,sf,0);if(state==MAP_FAILED)return 1;
 if(state->magic!=0x52583332)*state=(struct ui_state){0x52583332,{1,.6,0,1,.5,.5},0,1};
 state->shutdown_show=0;state->shutdown_progress=0;state->pressed&=~((1u<<4)|(1u<<5));
 int W=1280,H=720;{int fb=open(fb_device(),O_RDONLY);if(fb>=0){struct fb_var_screeninfo v;if(!ioctl(fb,FBIOGET_VSCREENINFO,&v)){W=v.xres;H=v.yres;}close(fb);}}
 struct layout L=make_layout(W,H,rotation_for(W,H));
 struct input_absinfo ax={.maximum=W-1},ay={.maximum=H-1};struct finger fingers[10]={0};
 if(!replay&&!mouse&&(ioctl(in,EVIOCGABS(ABS_MT_POSITION_X),&ax)||ioctl(in,EVIOCGABS(ABS_MT_POSITION_Y),&ay))){perror("touch ranges");return 1;}
 fprintf(stderr,"touch bridge: %s, panel %dx%d rotate %d, logical %dx%d, firmware %dx%d at %d,%d, touch %d..%d x %d..%d\n",
  mouse?"mouse":replay?"replay (firmware coordinates)":"touchscreen",W,H,L.rot,L.LW,L.LH,L.cw,L.ch,L.cx,L.cy,ax.minimum,ax.maximum,ay.minimum,ay.maximum);
 if(mouse){fingers[0].x=L.LW/2;fingers[0].y=L.LH/2;state->cursor_x=fingers[0].x;state->cursor_y=fingers[0].y;state->cursor_visible=1;fprintf(stderr,"mouse mode: left=touch, wheel=browse, right=back, middle=enter\n");}
 int browse_idx=key_index(0x202);
 long power_armed_at=0;
 /* Explicit SOURCE click arms only after the real page stays visible. */
 long source_requested_at=0,source_stable_since=0;
 (void)open_source_fb();
 int slot=0,source=-1,ux=0,uy=0,release=0;struct input_event e;struct pollfd p={in,POLLIN,0};
 for(;;){
  int ready=poll(&p,1,10);if(ready<0)return 1;
  if(ready){if(read(in,&e,sizeof(e))!=sizeof(e))break;
   if(mouse){struct finger*f=&fingers[0];
    if(e.type==EV_REL){if(e.code==REL_X)f->x+=e.value;if(e.code==REL_Y)f->y+=e.value;if(f->x<0)f->x=0;if(f->x>L.LW-1)f->x=L.LW-1;if(f->y<0)f->y=0;if(f->y>L.LH-1)f->y=L.LH-1;
     if(e.code==REL_WHEEL&&e.value)command(0x420c,4,0,e.value>0?-1:1,0);}
    if(e.type==EV_KEY){if(e.code==BTN_LEFT)f->down=e.value;if(e.code==BTN_RIGHT&&e.value<2)command(0x420d,e.value?0:2,0,0,0);if(e.code==BTN_MIDDLE&&e.value<2)command(0x420c,e.value?0:2,0,0,0);}
    state->cursor_x=f->x;state->cursor_y=f->y;}
   else if(e.type==EV_ABS){if(e.code==ABS_MT_SLOT)slot=e.value;if(slot>=0&&slot<10){struct finger*f=&fingers[slot];if(e.code==ABS_MT_POSITION_X)f->x=e.value;if(e.code==ABS_MT_POSITION_Y)f->y=e.value;if(e.code==ABS_MT_TRACKING_ID)f->down=e.value>=0;}}
   if(e.type!=EV_SYN||e.code!=SYN_REPORT)continue;
  }
  /* POWER now has a dedicated top-row hit target. It is armed only while
     a finger is continuously pressed inside that button for three seconds. */
  if(state->shutdown_show&&power_armed_at&&millis()-power_armed_at>30000){
   state->shutdown_show=0;state->shutdown_progress=0;
  }
  for(int i=0;i<10;i++){
   struct finger*f=&fingers[i];int lx,ly,fwx,fwy;
   if(replay){fwx=f->x;fwy=f->y;lx=L.cx+(int)(fwx*L.sx);ly=L.cy+(int)(fwy*L.sy);}
   else{if(mouse){lx=f->x;ly=f->y;}else{int px=(int)((long)(f->x-ax.minimum)*W/(ax.maximum-ax.minimum+1)),py=(int)((long)(f->y-ay.minimum)*H/(ay.maximum-ay.minimum+1));panel_to_logical(&L,px,py,&lx,&ly);}
    fwx=(int)((lx-L.cx)/L.sx);fwy=(int)((ly-L.cy)/L.sy);}
   if(fwx<0)fwx=0;if(fwx>FW_W-1)fwx=FW_W-1;if(fwy<0)fwy=0;if(fwy>FW_H-1)fwy=FW_H-1;
   if(f->down&&!f->active){f->active=1;int b=button_at(&L,lx,ly);
    if(b==5){
     /* POWER: local host-side continuous-hold shutdown, never forwarded to firmware. */
     f->region=-2;f->down_at=millis();
     state->pressed|=1u<<5;
     state->shutdown_show=1;state->shutdown_progress=0;power_armed_at=millis();
    }else if(b>=0){f->region=1+b;f->escalated=0;f->down_at=millis();
      if(b!=0){state->shutdown_show=0;state->shutdown_progress=0;}
      if(b==browse_idx){state->pressed|=1u<<b;}                 /* key send deferred until tap-vs-hold is known */
      else if(b==4)state->pressed|=1u<<b; /* SEARCH: issue native firmware tap on finger release */
      else button(b,1);
    }else if(lx>=L.cx&&lx<L.cx+L.cw&&ly>=L.cy&&ly<L.cy+L.ch&&source<0){
     state->shutdown_show=0;state->shutdown_progress=0;
     source=i;f->region=0;
    }else f->region=-1;
    fprintf(stderr,"touch begin slot=%d logical=%d,%d firmware=%d,%d region=%d\n",i,lx,ly,fwx,fwy,f->region);
   }
   if(f->active&&f->down&&f->region==0){ux=fwx;uy=fwy;}
   if(f->active&&f->down&&f->region==-2){
    if(!state->shutdown_show||button_at(&L,lx,ly)!=5){
     state->shutdown_progress=0;state->shutdown_show=0;state->pressed&=~(1u<<5);f->region=-1; /* leaving cancels */
    }else{
     long elapsed=millis()-f->down_at;
     unsigned progress=(unsigned)(elapsed*100/RX3_POWER_HOLD_MS);
     if(progress>100)progress=100;
     /* Throttle visual redraws to 5-percent steps. */
     state->shutdown_progress=(progress/5)*5;
     if(elapsed>=RX3_POWER_HOLD_MS){
      if(request_poweroff()){
       f->region=-3;state->shutdown_progress=100;
       fprintf(stderr,"RX3 POWER OFF: 3-second hold, requested system shutdown\n");
      }else{state->shutdown_progress=0;f->region=-1;}
     }
    }
   }
   if(browse_idx>=0&&f->active&&f->down&&f->region==1+browse_idx&&!f->escalated&&millis()-f->down_at>=SHORTCUT_HOLD_MS){
    f->escalated=1;state->pressed&=~(1u<<browse_idx);shortcut_open();}
   if(f->active&&!f->down){
    if(f->region>0){int b=f->region-1;
      if(b==browse_idx){state->pressed&=~(1u<<b);if(!f->escalated)browse_tap();}
      else if(b==4){state->pressed&=~(1u<<b);command(0x0205,0,0,0,0);command(0x0205,2,0,0,0);} else button(b,0);
      if(b==0){state->shutdown_show=0;state->shutdown_progress=0;}
    }
    if(f->region==-2){state->shutdown_progress=0;state->shutdown_show=0;state->pressed&=~(1u<<5);} /* release cancels */
    if(source==i){source=-1;release=10;}f->active=0;
   }
  }
  if(source>=0||release){struct report r={source>=0,0,37+(FW_W-ux)*3976/FW_W,72+uy*3856/FW_H};if(write(out,&r,sizeof(r))!=sizeof(r))perror("touch report");if(source<0)release--;}
 }
 for(int i=0;i<10;i++)if(fingers[i].active&&fingers[i].region>0){int b=fingers[i].region-1;
  if(b==browse_idx){if(!fingers[i].escalated)browse_tap();}else if(b==4)state->pressed&=~(1u<<b); else button(b,0);}
 return 0;
}
