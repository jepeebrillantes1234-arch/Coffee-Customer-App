from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

OUT = Path(__file__).parent
W, H = 1920, 1080
BG = '#F7F3EC'; INK = '#2B2926'; MUTED = '#68747A'; BROWN = '#5A3828'; MED = '#765039'; CARAMEL = '#B58A55'; TEAL = '#2D676A'; PALE = '#E7EFED'; GOLD = '#FFF3D9'; WHITE = '#FFFFFF'; BLUE = '#405F80'; GREEN = '#4C7A63'; RED = '#A44A3F'
FONT = r'C:\Windows\Fonts\segoeui.ttf'; FONT_B = r'C:\Windows\Fonts\segoeuib.ttf'
def font(size, bold=False): return ImageFont.truetype(FONT_B if bold else FONT, size)
def wrap(draw, text, f, maxw):
    words = text.split(); lines=[]; cur=''
    for w in words:
        cand = f'{cur} {w}'.strip()
        if draw.textbbox((0,0), cand, font=f)[2] <= maxw or not cur: cur=cand
        else: lines.append(cur); cur=w
    if cur: lines.append(cur)
    return lines
def center_text(draw, box, text, f, fill, maxw=None, spacing=6):
    x1,y1,x2,y2=box; maxw=maxw or x2-x1-28
    base=max(14,f.size); spacing=min(spacing,4)
    while True:
        f=font(base,True); lines=wrap(draw,text,f,maxw); heights=[draw.textbbox((0,0),s,font=f)[3] for s in lines]
        total=sum(heights)+spacing*(len(heights)-1)
        if total <= y2-y1-12 or base <= 12: break
        base-=1
    y=y1+(y2-y1-total)/2
    for line,hh in zip(lines,heights):
        bb=draw.textbbox((0,0),line,font=f); draw.text(((x1+x2-(bb[2]-bb[0]))/2,y),line,font=f,fill=fill); y+=hh+spacing

def rr(draw, box, fill, outline, r=18, width=3): draw.rounded_rectangle(box,radius=r,fill=fill,outline=outline,width=width)
def arrow(draw, a, b, color=MED, width=4, label=None):
    x1,y1=a; x2,y2=b
    draw.line((x1,y1,x2,y2),fill=color,width=width)
    import math
    ang=math.atan2(y2-y1,x2-x1); size=14
    pts=[(x2,y2),(x2-size*math.cos(ang-0.5),y2-size*math.sin(ang-0.5)),(x2-size*math.cos(ang+0.5),y2-size*math.sin(ang+0.5))]
    draw.polygon(pts,fill=color)
    if label:
        mid=((x1+x2)/2,(y1+y2)/2); f=font(18,True); bb=draw.textbbox((0,0),label,font=f); draw.rounded_rectangle((mid[0]-bb[2]/2-7,mid[1]-bb[3]/2-3,mid[0]+bb[2]/2+7,mid[1]+bb[3]/2+3),radius=7,fill=BG); draw.text((mid[0]-bb[2]/2,mid[1]-bb[3]/2),label,font=f,fill=TEAL)

def shape(draw, box, kind, text, accent=MED):
    x1,y1,x2,y2=box
    if kind=='start':
        draw.ellipse(box,fill=WHITE,outline=accent,width=4)
    elif kind=='decision':
        draw.polygon([( (x1+x2)//2,y1),(x2,(y1+y2)//2),((x1+x2)//2,y2),(x1,(y1+y2)//2)],fill=GOLD,outline=CARAMEL)
        draw.line([( (x1+x2)//2,y1),(x2,(y1+y2)//2),((x1+x2)//2,y2),(x1,(y1+y2)//2),((x1+x2)//2,y1)],fill=CARAMEL,width=4)
    elif kind=='io':
        off=24; draw.polygon([(x1+off,y1),(x2,y1),(x2-off,y2),(x1,y2)],fill=WHITE,outline=accent)
        draw.line([(x1+off,y1),(x2,y1),(x2-off,y2),(x1,y2),(x1+off,y1)],fill=accent,width=4)
    else:
        rr(draw,box,WHITE,accent,18,4)
    center_text(draw,box,text,font(21,True),INK,maxw=(x2-x1)-50)

def make_page(filename, title, subtitle, columns, footnote=None):
    im=Image.new('RGB',(W,H),BG); d=ImageDraw.Draw(im)
    d.rectangle((0,0,W,18),fill=TEAL)
    d.text((80,52),'KJM COFFEE SHOP  |  CUSTOMER SYSTEM',font=font(21,True),fill=TEAL)
    d.text((80,92),title,font=font(48,True),fill=INK)
    d.text((80,155),subtitle,font=font(22),fill=MUTED)
    d.text((W-80,64),'VERIFIED FLOW',font=font(18,True),fill=MED,anchor='ra')
    margin=72; gap=26; top=230; bottom=965; colw=(W-2*margin-2*gap)//3
    for ci,col in enumerate(columns):
        x=margin+ci*(colw+gap); x2=x+colw
        rr(d,(x,top,x2,bottom), '#EFE8DE', '#D9D0C4', 22, 2)
        d.text((x+22,top+18),col['title'],font=font(22,True),fill=col.get('color',TEAL))
        items=col['items']; inner_top=top+72; usable=bottom-inner_top-25; n=len(items); step=usable//max(1,n); nodeh=min(116,step-30)
        if n>4: nodeh=min(90,step-25)
        for i,item in enumerate(items):
            cy=inner_top+i*step; bx1=x+24; bx2=x2-24; by1=cy; by2=cy+nodeh
            kind=item.get('kind','process'); branch=item.get('branch')
            if branch:
                # leave a branch lane on the right, while keeping the primary route centered
                bx2=x+colw*0.64
            shape(d,(bx1,by1,bx2,by2),kind,item['text'],item.get('accent',col.get('color',TEAL)))
            if i < n-1:
                main_label=item.get('next_label')
                if not main_label and kind=='decision' and branch:
                    if branch.strip().upper().startswith('NO'):
                        main_label='YES'
                    elif branch.strip().upper().startswith('YES'):
                        main_label='NO'
                arrow(d,((bx1+bx2)//2,by2+4),((bx1+bx2)//2,cy+step-7),TEAL,3,main_label)
            if branch:
                cb=(bx2+12,by1+5,x2-18,by2-5)
                rr(d,cb,'#F8E8E5',RED,14,2)
                center_text(d,cb,branch,font(16,True),RED,maxw=cb[2]-cb[0]-18,spacing=3)
                arrow(d,(bx2, (by1+by2)//2),(cb[0],(cb[1]+cb[3])//2),RED,2)
        if ci<2:
            arrow(d,(x2+3,(top+bottom)//2),(x2+gap-3,(top+bottom)//2),CARAMEL,4)
    if footnote:
        d.text((80,1010),footnote,font=font(16),fill=MUTED)
    path=OUT/filename; im.save(path,dpi=(180,180)); return im

pages=[]
pages.append(make_page('customer_flow_01_overview.png','Customer Journey Overview','Splash and account entry → shopping and checkout → order completion, membership, support, or logout.',[
 {'title':'1  ENTRY & ACCOUNT','color':TEAL,'items':[
  {'kind':'start','text':'Start: launch customer app'},
  {'kind':'process','text':'Initialize session, theme and services'},
  {'kind':'decision','text':'Saved customer session?','branch':'NO → Get Started → Login or Register'},
  {'kind':'process','text':'Authenticate with Laravel; open Home'},
 ]},
 {'title':'2  SHOP & COMPLETE ORDER','color':BLUE,'items':[
  {'kind':'process','text':'Browse Home / Menu and product details'},
  {'kind':'process','text':'Choose options; add products to Cart'},
  {'kind':'io','text':'Checkout: Pickup or Delivery, address, payment'},
  {'kind':'decision','text':'QRPh or cash/COD?','branch':'QRPh → payment flow','next_label':'COD'},
  {'kind':'process','text':'My Orders → Pickup or Delivery tracking'},
 ]},
 {'title':'3  OTHER CUSTOMER TASKS','color':GREEN,'items':[
  {'kind':'decision','text':'Choose another feature','branch':'Membership → payment and rewards','next_label':'Other features'},
  {'kind':'process','text':'Customer Service chat and Admin handoff'},
  {'kind':'decision','text':'Logout confirmed?','branch':'NO → stay signed in'},
  {'kind':'process','text':'Laravel logout; clear local session'},
  {'kind':'start','text':'End: Get Started'},
 ]}
], 'Full decision branches and server checks are in the detailed flowchart source files.'))

pages.append(make_page('customer_flow_02_auth_browse.png','Account, Browsing & Cart','Login and registration routes are separate from product discovery, but both lead to the same customer Home.',[
 {'title':'1  STARTUP','color':TEAL,'items':[
  {'kind':'start','text':'Start'},
  {'kind':'process','text':'Firebase, API token and theme initialization'},
  {'kind':'process','text':'Splash screen'},
  {'kind':'decision','text':'Cached session?','branch':'NO → Get Started'},
  {'kind':'decision','text':'Customer role?','branch':'NO → role router opens other app'},
 ]},
 {'title':'2  LOGIN / REGISTER','color':MED,'items':[
  {'kind':'decision','text':'Login or Register?','branch':'Login → credentials or Google sign-in','next_label':'Register'},
  {'kind':'io','text':'Register: name, username, email, phone and password'},
  {'kind':'process','text':'Laravel login / Google verification / registration'},
  {'kind':'decision','text':'Accepted?','branch':'NO → show error; retry or Forgot Password'},
  {'kind':'process','text':'Customer RootScreen → Home'},
 ]},
 {'title':'3  PRODUCT DISCOVERY','color':BLUE,'items':[
  {'kind':'process','text':'Load categories, products and home content'},
  {'kind':'process','text':'Open product details; select supported options'},
  {'kind':'decision','text':'Toggle favorite?','branch':'YES → update shared favorite state'},
  {'kind':'process','text':'Add selected product to cart'},
  {'kind':'decision','text':'Continue shopping?','branch':'NO → proceed to Checkout'},
 ]}
], 'Authentication fields/endpoints verified in Flutter auth screens and Laravel API routes.'))

pages.append(make_page('customer_flow_03_checkout_payment.png','Checkout & QRPh / COD Payment','Customer/Flutter submits the order; Laravel prices it; PayMongo processes QRPh and Laravel confirms payment.',[
 {'title':'1  CHECKOUT','color':TEAL,'items':[
  {'kind':'start','text':'Start from Cart'},
  {'kind':'decision','text':'Pickup or Delivery?','branch':'Delivery → select saved address and valid coordinates','next_label':'Pickup'},
  {'kind':'decision','text':'Shop open?','branch':'NO → cannot place new online order'},
  {'kind':'process','text':'Laravel preview calculates prices, fees and discounts'},
  {'kind':'io','text':'Submit order with stable request ID'},
 ]},
 {'title':'2  ORDER & PAYMENT','color':BLUE,'items':[
  {'kind':'process','text':'Laravel validates and idempotently creates order/payment'},
  {'kind':'decision','text':'QRPh selected?','branch':'NO → COD / supported cash order path'},
  {'kind':'process','text':'Create or reuse QRPh attempt'},
  {'kind':'decision','text':'QR details returned?','branch':'NO → safe retry with existing order/attempt'},
  {'kind':'process','text':'In-app QR; poll Laravel status'},
 ]},
 {'title':'3  FINAL STATE','color':GREEN,'items':[
  {'kind':'decision','text':'Server confirms Paid?','branch':'YES → success; then My Orders'},
  {'kind':'decision','text':'Still pending?','branch':'YES → continue checking; never trust QR display'},
  {'kind':'decision','text':'30-minute QRPh timeout?','branch':'YES → provider verifies unpaid; then cancel and hide from My Orders; record retained','next_label':'NO → keep pending'},
  {'kind':'process','text':'My Orders → tracking'},
 ]}
], 'Legacy Checkout Session may open external checkout if no QR image is returned. COD behavior remains separate.'))

pages.append(make_page('customer_flow_04_tracking_cancel.png','My Orders, Cancellation & Tracking','Payment and fulfillment status remain separate. Pickup and Delivery use distinct customer tracking views.',[
 {'title':'1  MY ORDERS','color':TEAL,'items':[
  {'kind':'start','text':'Open My Orders'},
  {'kind':'process','text':'Laravel returns customer-owned, non-archived orders'},
  {'kind':'decision','text':'QRPh pending / failed / expired?','branch':'YES → Pay Now reuses order and payment flow'},
  {'kind':'decision','text':'Fulfillment type?','branch':'Pickup → shop location; no rider map','next_label':'Delivery'},
  {'kind':'process','text':'Delivery → timeline, destination and rider map when available'},
 ]},
 {'title':'2  STATUS & COMPLETION','color':BLUE,'items':[
  {'kind':'process','text':'Pickup: pending → confirmed → preparing → ready → completed'},
  {'kind':'process','text':'Delivery: confirmed → preparing → ready → rider → delivered'},
  {'kind':'decision','text':'Terminal completed state?','branch':'YES → retain completed order/history'},
  {'kind':'process','text':'Live rider location only when available and fresh'},
  {'kind':'start','text':'Order complete'},
 ]},
 {'title':'3  CANCELLATION','color':RED,'items':[
  {'kind':'decision','text':'Eligible status and no paid payment?','branch':'NO → paid/progressed order needs support'},
  {'kind':'io','text':'Customer enters reason and confirms'},
  {'kind':'process','text':'Laravel locks row and rechecks eligibility'},
  {'kind':'decision','text':'Still eligible?','branch':'NO → reject; keep order unchanged'},
  {'kind':'process','text':'Cancel, save reason/time; retain history'},
 ]}
], 'No separate persisted “Already Picked Up” state was found; pickup uses the shared `ready` and `completed` statuses.'))

pages.append(make_page('customer_flow_05_membership_rewards.png','Membership, Loyalty & Card Delivery','Membership activation requires confirmed payment. Physical card delivery has its own request and status records.',[
 {'title':'1  MEMBERSHIP','color':TEAL,'items':[
  {'kind':'start','text':'Open Membership'},
  {'kind':'process','text':'Load membership, payment, points and rewards summary'},
  {'kind':'decision','text':'Active and paid?','branch':'NO → optionally start membership checkout'},
  {'kind':'process','text':'QRPh payment; Laravel confirms webhook/status'},
  {'kind':'process','text':'Activate membership idempotently after confirmation'},
 ]},
 {'title':'2  POINTS & REWARDS','color':GREEN,'items':[
  {'kind':'process','text':'Eligible paid delivered order earns loyalty points'},
  {'kind':'decision','text':'Enough points and stock?','branch':'NO → keep browsing rewards'},
  {'kind':'decision','text':'Pickup or Delivery fulfillment?','branch':'Delivery → choose saved address and quote','next_label':'Store Pickup'},
  {'kind':'process','text':'Laravel locks and records redemption; deducts points/stock'},
  {'kind':'start','text':'Redemption recorded'},
 ]},
 {'title':'3  PHYSICAL CARD','color':BLUE,'items':[
  {'kind':'decision','text':'Request card delivery?','branch':'NO → continue membership use'},
  {'kind':'io','text':'Review saved address, map pin and delivery notes'},
  {'kind':'decision','text':'Active + paid and no duplicate?','branch':'NO → reject or show existing request'},
  {'kind':'process','text':'Save separate Pending card-delivery snapshot'},
  {'kind':'process','text':'Staff prepares/assigns; rider updates to Delivered'},
 ]}
], 'Product-order delivery tracking and membership-card delivery records are separate systems.'))

pages.append(make_page('customer_flow_06_support_logout.png','Customer Support & Logout','Support history is persisted; handoff messaging reflects actual notification creation and does not promise an immediate human reply.',[
 {'title':'1  SUPPORT ENTRY','color':TEAL,'items':[
  {'kind':'start','text':'Open Customer Service'},
  {'kind':'decision','text':'Signed in?','branch':'NO → enter guest name/contact; guest token'},
  {'kind':'process','text':'Load customer or guest conversation'},
  {'kind':'io','text':'Send message, optional image or order link'},
  {'kind':'process','text':'Laravel stores message'},
 ]},
 {'title':'2  ASSISTANCE','color':BLUE,'items':[
  {'kind':'process','text':'Existing assistant replies using available context'},
  {'kind':'decision','text':'Human help needed/requested?','branch':'NO → continue chat'},
  {'kind':'process','text':'Create Admin notification / queue handoff'},
  {'kind':'decision','text':'Wait or contact Admin?','branch':'Contact → show configured contact details','next_label':'Wait'},
  {'kind':'process','text':'Conversation history remains available'},
 ]},
 {'title':'3  END SESSION','color':MED,'items':[
  {'kind':'process','text':'Return to Home or Profile'},
  {'kind':'decision','text':'Choose Logout?','branch':'NO → continue current session'},
  {'kind':'decision','text':'Confirm logout?','branch':'NO → return to Profile'},
  {'kind':'process','text':'Laravel logout and clear local session'},
  {'kind':'start','text':'End at Get Started'},
 ]}
], 'Support assistant and notification behavior verified in existing support API and service.'))

pdf=OUT/'customer_system_flowchart.pdf'
pages[0].save(pdf,save_all=True,append_images=pages[1:],resolution=180)
print('Rendered',len(pages),'PNG pages and',pdf)



