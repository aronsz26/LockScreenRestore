# Makes the Sileo banner (depiction/banner.jpg) and icon (depiction/icon.png) from the README screenshots.
# Run: python3 depiction/tools/make_art.py
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
R=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
F='/System/Library/Fonts/SFNS.ttf'
def font(size, weight=400):
    f=ImageFont.truetype(F,size)
    f.set_variation_by_axes([100, min(96,max(17,size)), 400, weight])
    return f
def gradient(w,h,c1,c2,c3):
    img=Image.new('RGB',(w,h))
    px=img.load()
    for y in range(h):
        for x in range(w):
            t=(x/w*0.65+y/h*0.35)
            if t<0.5: a,b,u=c1,c2,t/0.5
            else: a,b,u=c2,c3,(t-0.5)/0.5
            px[x,y]=tuple(int(a[i]+(b[i]-a[i])*u) for i in range(3))
    return img
def phone(shot, width):
    s=Image.open(shot).convert('RGB')
    h=int(s.height*width/s.width)
    s=s.resize((width,h),Image.LANCZOS)
    pad=int(width*0.035); r=int(width*0.14)
    frame=Image.new('RGBA',(width+2*pad,h+2*pad),(0,0,0,0))
    d=ImageDraw.Draw(frame); d.rounded_rectangle([0,0,frame.width-1,frame.height-1],radius=r+pad,fill=(18,18,22,255))
    mask=Image.new('L',(width,h),0); ImageDraw.Draw(mask).rounded_rectangle([0,0,width-1,h-1],radius=r,fill=255)
    frame.paste(s,(pad,pad),mask)
    return frame
def shadowed(base, layer, pos, blur=30, off=(0,18), alpha=140):
    sh=Image.new('RGBA',base.size,(0,0,0,0))
    a=layer.split()[3].point(lambda v: min(v,alpha))
    blk=Image.new('RGBA',layer.size,(0,0,0,255)); blk.putalpha(a)
    sh.paste(blk,(pos[0]+off[0],pos[1]+off[1]),blk)
    sh=sh.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(sh); base.alpha_composite(layer,pos)
# banner
W,H=1500,750
b=gradient(W,H,(22,10,44),(70,30,110),(150,60,140)).convert('RGBA')
glow=Image.new('RGBA',(W,H),(0,0,0,0)); ImageDraw.Draw(glow).ellipse([450,150,1050,900],fill=(230,120,220,60)); b.alpha_composite(glow.filter(ImageFilter.GaussianBlur(140)))
p=phone(os.path.join(R,'screenshots','lockscreen.jpg'),330)
shadowed(b,p,((W-p.width)//2,200),blur=40,off=(0,24),alpha=160)
b.convert('RGB').save(os.path.join(R,'depiction','banner.jpg'),quality=90)
# icon
S=512
ic=gradient(S,S,(40,18,80),(110,44,160),(210,80,150)).convert('RGBA')
lay=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(lay)
cx=S//2; t=30
# open shackle: arc over the right half, lifted, left leg short
d.arc([cx-62,70,cx+98,230],start=180,end=360,fill='white',width=t)
d.rectangle([cx+98-t,150,cx+98,215],fill='white')
d.rectangle([cx-62,150,cx-62+t,172],fill='white')
d.ellipse([cx-62,172-t//2,cx-62+t,172+t//2],fill='white')
d.rounded_rectangle([cx-125,205,cx+125,385],radius=36,fill='white')
d.text((cx,296),'15',font=font(118,700),fill=(90,36,140,255),anchor='mm')
ic.alpha_composite(lay)
ic.convert('RGB').save(os.path.join(R,'depiction','icon.png'))
print('ok')
print('ok')
