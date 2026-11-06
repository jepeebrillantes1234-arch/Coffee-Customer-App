from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math

OUT = Path(__file__).parent
W, H = 1920, 1080
BG, INK, MUTED = '#F7F3EC', '#2B2926', '#68747A'
TEAL, BROWN, CARAMEL, BLUE, GREEN, RED = '#2D676A', '#765039', '#B58A55', '#405F80', '#4C7A63', '#A44A3F'
WHITE, PANEL, GOLD, BRANCH = '#FFFFFF', '#EFE8DE', '#FFF3D9', '#F8E8E5'
FONT = r'C:\Windows\Fonts\segoeui.ttf'
FONT_B = r'C:\Windows\Fonts\segoeuib.ttf'

def f(size, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, size)

def wrap(draw, text, face, width):
    lines, current = [], ''
    for word in text.split():
        candidate = f'{current} {word}'.strip()
        if draw.textbbox((0, 0), candidate, font=face)[2] <= width or not current:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines

def centered(draw, box, text, size=20, color=INK, max_width=None, bold=True):
    x1, y1, x2, y2 = box
    max_width = max_width or (x2 - x1 - 28)
    face_size = size
    while True:
        face = f(face_size, bold)
        lines = wrap(draw, text, face, max_width)
        heights = [draw.textbbox((0, 0), line, font=face)[3] for line in lines]
        line_gap = 3
        total = sum(heights) + line_gap * (len(lines) - 1)
        if total <= y2 - y1 - 12 or face_size <= 13:
            break
        face_size -= 1
    y = y1 + (y2 - y1 - total) / 2
    for line, height in zip(lines, heights):
        bounds = draw.textbbox((0, 0), line, font=face)
        draw.text(((x1 + x2 - (bounds[2] - bounds[0])) / 2, y), line, font=face, fill=color)
        y += height + line_gap

def arrow(draw, start, end, color=TEAL, width=3, label=None):
    x1, y1 = start
    x2, y2 = end
    draw.line((x1, y1, x2, y2), fill=color, width=width)
    angle = math.atan2(y2 - y1, x2 - x1)
    size = 13
    draw.polygon([
        (x2, y2),
        (x2 - size * math.cos(angle - .5), y2 - size * math.sin(angle - .5)),
        (x2 - size * math.cos(angle + .5), y2 - size * math.sin(angle + .5)),
    ], fill=color)
    if label:
        face = f(16, True)
        bounds = draw.textbbox((0, 0), label, font=face)
        x, y = (x1 + x2) / 2, (y1 + y2) / 2
        draw.rounded_rectangle((x - bounds[2] / 2 - 6, y - 12, x + bounds[2] / 2 + 6, y + 12), radius=6, fill=BG)
        draw.text((x - bounds[2] / 2, y - 10), label, font=face, fill=TEAL)

def node(draw, box, item, accent):
    x1, y1, x2, y2 = box
    kind = item.get('kind', 'process')
    if kind == 'start':
        draw.ellipse(box, fill=WHITE, outline=accent, width=4)
    elif kind == 'decision':
        points = [((x1+x2)//2, y1), (x2, (y1+y2)//2), ((x1+x2)//2, y2), (x1, (y1+y2)//2)]
        draw.polygon(points, fill=GOLD)
        draw.line(points + [points[0]], fill=CARAMEL, width=4)
    elif kind == 'io':
        skew = 22
        points = [(x1+skew,y1),(x2,y1),(x2-skew,y2),(x1,y2)]
        draw.polygon(points, fill=WHITE)
        draw.line(points + [points[0]], fill=accent, width=4)
    else:
        draw.rounded_rectangle(box, radius=16, fill=WHITE, outline=accent, width=4)
    centered(draw, box, item['text'], max_width=(x2-x1)-42)

def render(filename, title, subtitle, columns, footnote=''):
    image = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0,0,W,16), fill=TEAL)
    draw.text((74,44), 'KJM COFFEE SHOP  |  CUSTOMER SYSTEM FLOW', font=f(19, True), fill=TEAL)
    draw.text((74,78), title, font=f(43, True), fill=INK)
    draw.text((74,139), subtitle, font=f(20), fill=MUTED)
    left, right, top, bottom, gap = 64, 64, 216, 978, 22
    colw = (W-left-right-gap*2)//3
    for ci, col in enumerate(columns):
        x1 = left + ci*(colw+gap)
        x2 = x1 + colw
        draw.rounded_rectangle((x1,top,x2,bottom), radius=20, fill=PANEL, outline='#D9D0C4', width=2)
        draw.text((x1+20,top+15), col['title'], font=f(20,True), fill=col.get('accent',TEAL))
        items = col['items']
        content_top, content_bottom = top+62, bottom-18
        step = (content_bottom-content_top)//len(items)
        height = min(110, step-18)
        for index, item in enumerate(items):
            y1 = content_top + index*step
            y2 = y1 + height
            has_branch = bool(item.get('branch'))
            nx1, nx2 = x1+18, x2-18
            if has_branch:
                nx2 = x1 + int(colw*.60)
            node(draw,(nx1,y1,nx2,y2),item,col.get('accent',TEAL))
            if index < len(items)-1:
                label = item.get('next_label')
                if not label and item.get('kind') == 'decision' and has_branch:
                    branch_upper = item['branch'].strip().upper()
                    label = 'YES' if branch_upper.startswith('NO') else ('NO' if branch_upper.startswith('YES') else None)
                arrow(draw,((nx1+nx2)//2,y2+3),((nx1+nx2)//2,y1+step-4),TEAL,3,label)
            if has_branch:
                bx1, bx2 = nx2+9, x2-14
                by1, by2 = y1+5, y2-5
                draw.rounded_rectangle((bx1,by1,bx2,by2),radius=12,fill=BRANCH,outline=RED,width=2)
                centered(draw,(bx1+4,by1+2,bx2-4,by2-2),item['branch'],size=15,color=RED,max_width=bx2-bx1-16)
                arrow(draw,(nx2,(y1+y2)//2),(bx1,(by1+by2)//2),RED,2)
        if ci < 2:
            arrow(draw,(x2+2,(top+bottom)//2),(x2+gap-2,(top+bottom)//2),CARAMEL,4)
    if footnote:
        draw.text((74,1015),footnote,font=f(15),fill=MUTED)
    image.save(OUT/filename,dpi=(180,180))

render('customer_flow_01_main_entry_browse.png','Main Customer System Flowchart — App Entry & Shopping','Part 1 of 2 · Startup, login/register, Home, product discovery, and cart.',[
 {'title':'APP START & SESSION','accent':TEAL,'items':[
  {'kind':'start','text':'Open Mobile App'},
  {'kind':'process','text':'Initialize Firebase, API session, theme and services'},
  {'kind':'process','text':'Show Splash Screen and restore saved session'},
  {'kind':'decision','text':'Authenticated customer session?','branch':'NO → Login or Register','next_label':'YES'},
  {'kind':'io','text':'Login: email/username/phone + password or Google; Register: account details'},
  {'kind':'decision','text':'Laravel accepts login or registration?','branch':'NO → Show error; retry or Forgot Password'},
  {'kind':'process','text':'Open Customer Home'},
 ]},
 {'title':'HOME & DISCOVERY','accent':BLUE,'items':[
  {'kind':'process','text':'Load categories, products, banners, app config and shop hours'},
  {'kind':'decision','text':'Home data loaded?','branch':'NO → Show available error/empty state; retry'},
  {'kind':'process','text':'Browse Home and Menu categories'},
  {'kind':'io','text':'Search products; open Promos, discounts and best sellers'},
  {'kind':'process','text':'Open product details and select supported options'},
  {'kind':'decision','text':'Add product to cart?','branch':'NO → Return to browsing'},
  {'kind':'process','text':'Cart updated'},
 ]},
 {'title':'CART REVIEW','accent':GREEN,'items':[
  {'kind':'process','text':'Review cart items and selected options'},
  {'kind':'decision','text':'Change cart?','branch':'YES → Update quantity, remove or edit item','next_label':'NO'},
  {'kind':'decision','text':'Continue shopping or Checkout?','branch':'Continue → return to product browsing','next_label':'Checkout'},
  {'kind':'process','text':'Proceed to Checkout'},
 ]},
], 'Main continuation: see Part 2 and the detailed Checkout and Payment flowchart.')

render('customer_flow_02_main_order_destinations.png','Main Customer System Flowchart — Orders & Other Destinations','Part 2 of 2 · Checkout, order completion, membership/rewards, customer service, profile and logout.',[
 {'title':'ORDER JOURNEY','accent':BLUE,'items':[
  {'kind':'process','text':'Checkout: choose Delivery or Pickup; select eligible payment'},
  {'kind':'decision','text':'QRPh selected?','branch':'YES → PayMongo QRPh; Laravel verifies payment','next_label':'COD / pickup cash'},
  {'kind':'process','text':'Order confirmation and My Orders'},
  {'kind':'process','text':'Pickup or Delivery tracking'},
  {'kind':'start','text':'Delivered / picked up; order remains in history'},
 ]},
 {'title':'MEMBERSHIP & SERVICE','accent':GREEN,'items':[
  {'kind':'decision','text':'Choose Membership & Rewards?','branch':'YES → View/purchase membership, earn points, redeem reward, card delivery','next_label':'NO'},
  {'kind':'decision','text':'Choose Customer Service?','branch':'YES → Chat, assistant response and Admin handoff','next_label':'NO'},
  {'kind':'process','text':'Other Home/Profile destinations; return to Home when finished'},
 ]},
 {'title':'PROFILE & SIGN OUT','accent':TEAL,'items':[
  {'kind':'process','text':'Open Profile and account settings'},
  {'kind':'decision','text':'Confirm Logout?','branch':'NO → stay in current app session','next_label':'YES'},
  {'kind':'process','text':'Laravel logout; clear local session'},
  {'kind':'start','text':'Return to Login / Get Started'},
 ]},
], 'Payment, cancellation, rewards and support outcomes are detailed in the following flowcharts.')

render('customer_flow_03_checkout_payment.png','Checkout and Payment Flowchart','Address/fee validation, server pricing, eligible QRPh/COD/cash methods, retries, and unpaid expiry.',[
 {'title':'CHECKOUT INPUT','accent':TEAL,'items':[
  {'kind':'start','text':'Start Checkout from Cart'},
  {'kind':'decision','text':'Valid available cart items?','branch':'NO → Return to Cart and update items','next_label':'YES'},
  {'kind':'decision','text':'Delivery or Pickup?','branch':'Pickup → no delivery address/fee','next_label':'Delivery'},
  {'kind':'io','text':'Delivery: select saved address and map pin'},
  {'kind':'decision','text':'Complete address and coordinates?','branch':'NO → Select/review address','next_label':'YES'},
  {'kind':'process','text':'Laravel quotes delivery fee and authoritative order totals'},
  {'kind':'decision','text':'Shop open for new orders?','branch':'NO → Show closed/unavailable; do not submit'},
 ]},
 {'title':'ORDER & METHOD','accent':BLUE,'items':[
  {'kind':'process','text':'Review subtotal, discounts, fee and final total'},
  {'kind':'decision','text':'Choose eligible payment','branch':'Delivery: COD · Pickup: Cash at Pickup · QRPh when enabled'},
  {'kind':'io','text':'Submit order with stable checkout request ID'},
  {'kind':'process','text':'Laravel validates and idempotently creates order/payment'},
  {'kind':'decision','text':'Order created?','branch':'NO → Show validation/network error; retry safely','next_label':'YES'},
  {'kind':'decision','text':'QRPh order?','branch':'NO → COD/cash remains unpaid until cash collection'},
 ]},
 {'title':'QRPH STATUS','accent':GREEN,'items':[
  {'kind':'process','text':'PayMongo creates or reuses QRPh payment details'},
  {'kind':'decision','text':'QR details returned?','branch':'NO → Retry existing order/payment attempt'},
  {'kind':'process','text':'Show QR, amount, reference, expiry and instructions'},
  {'kind':'decision','text':'Laravel confirms Paid?','branch':'YES → Show success; then My Orders'},
  {'kind':'decision','text':'Still pending / failed / expired?','branch':'Pending → check again · Failed/expired → retry if permitted'},
  {'kind':'decision','text':'30-minute unpaid timeout?','branch':'YES → Provider must confirm unpaid before backend expiry'},
  {'kind':'process','text':'Expired QRPh order hidden from active list; records retained'},
 ]},
], 'Legacy Checkout Session can still open provider checkout when no QR image is returned.')

render('customer_flow_04_tracking_cancel.png','Order Tracking and Cancellation Flowchart','Payment state is separate from fulfillment. Pickup has no rider route; Delivery may show fresh rider GPS.',[
 {'title':'MY ORDERS & PAYMENT','accent':TEAL,'items':[
  {'kind':'start','text':'Open My Orders'},
  {'kind':'process','text':'Laravel returns this customer’s non-archived orders'},
  {'kind':'decision','text':'QRPh unpaid / failed / expired?','branch':'YES → Pay Now reuses order/payment flow','next_label':'NO'},
  {'kind':'decision','text':'Select Pickup or Delivery?','branch':'Pickup → status timeline and shop location','next_label':'Delivery'},
  {'kind':'process','text':'Delivery → destination and rider details when assigned'},
 ]},
 {'title':'FULFILLMENT STATUS','accent':BLUE,'items':[
  {'kind':'process','text':'Pickup shared states: pending → confirmed → preparing → ready → completed'},
  {'kind':'process','text':'Pickup ready label is “Ready for pickup”; no rider tracking'},
  {'kind':'decision','text':'Delivery rider assigned and GPS fresh?','branch':'NO → show status without live rider marker','next_label':'YES'},
  {'kind':'process','text':'Show rider profile, GPS marker and route when available'},
  {'kind':'process','text':'Delivery statuses progress through preparing, ready, rider en route, delivered'},
  {'kind':'start','text':'Completed order remains in history'},
 ]},
 {'title':'CANCELLATION','accent':RED,'items':[
  {'kind':'decision','text':'Backend cancellation eligible?','branch':'NO → paid/progressed order: contact Customer Service'},
  {'kind':'io','text':'Provide cancellation reason and confirm'},
  {'kind':'process','text':'Laravel locks order and rechecks status/payment'},
  {'kind':'decision','text':'Still eligible?','branch':'NO → reject; order remains unchanged','next_label':'YES'},
  {'kind':'process','text':'Set Cancelled, save reason/time/log, expire pending QR attempt'},
  {'kind':'start','text':'Cancelled order remains in history'},
 ]},
], 'Pickup persists shared `ready` and `completed` states; no separate “Already Picked Up” state was found.')

render('customer_flow_05_membership_rewards.png','Membership and Rewards Flowchart','Verified activation, eligible point earning, redemption code/history, and separate physical-card delivery.',[
 {'title':'MEMBERSHIP','accent':TEAL,'items':[
  {'kind':'start','text':'Open Membership'},
  {'kind':'process','text':'Load status, payment, Member ID, balance and rewards'},
  {'kind':'decision','text':'Active and paid?','branch':'NO → optionally purchase membership'},
  {'kind':'process','text':'QRPh payment; Laravel checks provider confirmation'},
  {'kind':'decision','text':'Payment confirmed?','branch':'NO → pending, failed/expired or retry; stay inactive','next_label':'YES'},
  {'kind':'process','text':'Laravel records Paid and activates membership'},
  {'kind':'process','text':'Display active membership card and Member ID/QR'},
 ]},
 {'title':'POINTS & REDEMPTION','accent':GREEN,'items':[
  {'kind':'process','text':'Eligible paid delivered/completed order with active membership'},
  {'kind':'process','text':'Laravel awards item-quantity points once and records transaction'},
  {'kind':'process','text':'Browse rewards and points/redemption history'},
  {'kind':'decision','text':'Active member, sufficient points and stock?','branch':'NO → show eligibility/availability message'},
  {'kind':'decision','text':'Pickup or Delivery redemption?','branch':'Delivery → choose saved address and fee quote','next_label':'Pickup'},
  {'kind':'process','text':'Laravel locks points/stock and records redemption'},
  {'kind':'process','text':'Display redemption QR/reference code and history'},
 ]},
 {'title':'PHYSICAL MEMBERSHIP CARD','accent':BLUE,'items':[
  {'kind':'decision','text':'Request physical card delivery?','branch':'NO → continue membership use'},
  {'kind':'io','text':'Review saved address, map pin, coordinates and delivery notes'},
  {'kind':'decision','text':'Active + paid and no existing request?','branch':'NO → reject or show existing request'},
  {'kind':'process','text':'Create separate delivery request/address snapshot'},
  {'kind':'process','text':'Staff prepares/assigns rider; card delivery tracked separately'},
  {'kind':'decision','text':'Card delivered?','branch':'NO → continue separate card-delivery status updates','next_label':'YES'},
  {'kind':'start','text':'Card delivered; membership payment remains Paid'},
 ]},
], 'Reward redemption shows the generated code as a QR and preserves redemption history.')

render('customer_flow_06_customer_service.png','Customer Service Flowchart','Authenticated or guest chat, local rule-based responses, persistent history, and Admin/staff escalation.',[
 {'title':'OPEN CHAT','accent':TEAL,'items':[
  {'kind':'start','text':'Open Customer Service'},
  {'kind':'decision','text':'Authenticated customer?','branch':'NO → enter guest contact or resume using guest token','next_label':'YES'},
  {'kind':'process','text':'Load own conversation and available order context'},
  {'kind':'io','text':'Send concern; optional image/order reference'},
  {'kind':'process','text':'Laravel validates and stores message'},
 ]},
 {'title':'ASSISTANCE & HANDOFF','accent':BLUE,'items':[
  {'kind':'process','text':'Local rule-based assistant matches message keywords/context'},
  {'kind':'decision','text':'Useful response available?','branch':'NO / human help requested → ask follow-up or offer Admin'},
  {'kind':'process','text':'Show automated reply; do not promise human response'},
  {'kind':'decision','text':'Wait or contact Admin directly?','branch':'Contact → show configured customer-service details','next_label':'Wait'},
  {'kind':'process','text':'Create/retain Admin handoff notification where implemented'},
 ]},
 {'title':'RETURN & ACCOUNT','accent':GREEN,'items':[
  {'kind':'process','text':'Refresh messages; retain conversation history'},
  {'kind':'decision','text':'Send another message?','branch':'YES → return to chat'},
  {'kind':'process','text':'Return to Home/Profile'},
  {'kind':'decision','text':'Confirm Logout?','branch':'NO → remain signed in','next_label':'YES'},
  {'kind':'process','text':'Laravel logout and clear local session'},
  {'kind':'start','text':'Return to Login / Get Started'},
 ]},
], 'The assistant is local rule/keyword matching; Admin notification indicates handoff, not an immediate human reply.')

print('Rendered six 16:9 PNG pages.')
