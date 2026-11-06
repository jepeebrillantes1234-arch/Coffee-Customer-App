"""Build a small editable-title, 16:9 OOXML deck from the verified flowchart pages.

The flowcharts stay as high-resolution PNGs so they remain crisp at presentation
size; their Mermaid sources are supplied alongside the deck for editing.
"""
from __future__ import annotations

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile
from xml.etree import ElementTree as ET
import html

OUTDIR = Path(__file__).parent
OUT = OUTDIR / "Customer_System_Flowcharts.pptx"
PAGES = [
    "customer_flow_01_main_entry_browse.png",
    "customer_flow_02_main_order_destinations.png",
    "customer_flow_03_checkout_payment.png",
    "customer_flow_04_tracking_cancel.png",
    "customer_flow_05_membership_rewards.png",
    "customer_flow_06_customer_service.png",
]
SW, SH = 12192000, 6858000  # 13.333 x 7.5 inches, 16:9

P = "http://schemas.openxmlformats.org/presentationml/2006/main"
A = "http://schemas.openxmlformats.org/drawingml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
CT = "http://schemas.openxmlformats.org/package/2006/content-types"
for prefix, uri in (("p", P), ("a", A), ("r", R)):
    ET.register_namespace(prefix, uri)

def esc(value: str) -> str:
    return html.escape(value, quote=True)

def rels(items: list[tuple[str, str, str]]) -> str:
    nodes = "".join(
        f'<Relationship Id="{rid}" Type="{typ}" Target="{target}"/>'
        for rid, typ, target in items
    )
    return f'<Relationships xmlns="{PKG}">{nodes}</Relationships>'

def shape_text(shape_id: int, name: str, x: int, y: int, cx: int, cy: int,
               text: str, *, size: int, color: str, bold: bool = False,
               tracking: int = 0) -> str:
    b = ' b="1"' if bold else ''
    sp = f'<p:sp><p:nvSpPr><p:cNvPr id="{shape_id}" name="{esc(name)}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
    sp += f'<p:spPr><a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr>'
    sp += '<p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0"/><a:lstStyle/><a:p><a:pPr algn="l"/><a:r><a:rPr lang="en-US" dirty="0" sz="{}"{}{}><a:solidFill><a:srgbClr val="{}"/></a:solidFill><a:latin typeface="Aptos"/></a:rPr><a:t>{}</a:t></a:r><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>'.format(size, b, f' spc="{tracking}"' if tracking else '', color, esc(text))
    return sp

def cover_slide() -> str:
    shapes = '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
    # Editable background and accent strip.
    shapes += f'<p:sp><p:nvSpPr><p:cNvPr id="2" name="Warm cream background"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{SW}" cy="{SH}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="F5F1E9"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>'
    shapes += f'<p:sp><p:nvSpPr><p:cNvPr id="3" name="Coffee teal header strip"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{SW}" cy="150000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="2D676A"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>'
    shapes += shape_text(4, "KJM Coffee Shop eyebrow", 900000, 1550000, 10200000, 450000, "KJM COFFEE SHOP  |  CUSTOMER JOURNEY", size=1900, color="2D676A", bold=True, tracking=120)
    shapes += shape_text(5, "Presentation title line 1", 900000, 2250000, 10500000, 850000, "Customer System", size=4200, color="20272D", bold=True)
    shapes += shape_text(6, "Presentation title line 2", 900000, 3130000, 10500000, 850000, "Flowcharts", size=4200, color="20272D", bold=True)
    shapes += shape_text(7, "Presentation subtitle", 920000, 4300000, 10000000, 850000, "End-to-end mobile customer experience, verified against the implemented Flutter app and Laravel backend.", size=1700, color="5E6A70")
    shapes += shape_text(8, "Diagram contents", 920000, 5400000, 10500000, 650000, "Main journey  •  Checkout & payment  •  Order tracking  •  Membership & rewards  •  Customer service", size=1450, color="765039", bold=True)
    shapes += shape_text(9, "Editable source note", 920000, 6250000, 10000000, 350000, "Flow diagrams are supplied as high-resolution images; Mermaid source files are included for editing.", size=1050, color="68747A")
    return f'<p:sld xmlns:a="{A}" xmlns:r="{R}" xmlns:p="{P}"><p:cSld><p:spTree>{shapes}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>'

def image_slide(rid: str, filename: str) -> str:
    pic = f'<p:pic><p:nvPicPr><p:cNvPr id="2" name="{esc(filename)}" descr="High-resolution flowchart page; matching Mermaid source is included."/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{SW}" cy="{SH}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>'
    tree = '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>' + pic
    return f'<p:sld xmlns:a="{A}" xmlns:r="{R}" xmlns:p="{P}"><p:cSld><p:spTree>{tree}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>'

def master() -> str:
    tree = '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
    return f'<p:sldMaster xmlns:a="{A}" xmlns:r="{R}" xmlns:p="{P}"><p:cSld><p:spTree>{tree}</p:spTree></p:cSld><p:clrMap accent1="2D676A" accent2="B9794A" accent3="405F80" accent4="4C7A63" accent5="B58A55" accent6="68747A" bg1="lt1" bg2="lt2" tx1="dk1" tx2="dk2" hlink="0563C1" folHlink="954F72"/><p:sldLayoutIdLst><p:sldLayoutId id="1" r:id="rId1"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>'

def layout() -> str:
    tree = '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
    return f'<p:sldLayout xmlns:a="{A}" xmlns:r="{R}" xmlns:p="{P}" type="blank" preserve="1"><p:cSld name="Blank"><p:spTree>{tree}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>'

def theme() -> str:
    return f'''<a:theme xmlns:a="{A}" name="KJM Coffee"><a:themeElements><a:clrScheme name="KJM Coffee"><a:dk1><a:srgbClr val="20272D"/></a:dk1><a:lt1><a:srgbClr val="F5F1E9"/></a:lt1><a:dk2><a:srgbClr val="5A3828"/></a:dk2><a:lt2><a:srgbClr val="FFFFFF"/></a:lt2><a:accent1><a:srgbClr val="2D676A"/></a:accent1><a:accent2><a:srgbClr val="B9794A"/></a:accent2><a:accent3><a:srgbClr val="405F80"/></a:accent3><a:accent4><a:srgbClr val="4C7A63"/></a:accent4><a:accent5><a:srgbClr val="B58A55"/></a:accent5><a:accent6><a:srgbClr val="68747A"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme><a:fontScheme name="Aptos"><a:majorFont><a:latin typeface="Aptos Display"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Aptos"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="KJM"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:lumMod val="80000"/></a:schemeClr></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:lumMod val="60000"/></a:schemeClr></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:lumMod val="95000"/><a:lumOff val="5000"/></a:schemeClr></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:lumMod val="90000"/><a:lumOff val="10000"/></a:schemeClr></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>'''

def main() -> None:
    missing = [name for name in PAGES if not (OUTDIR / name).is_file()]
    if missing:
        raise SystemExit(f"Missing rendered pages: {missing}")
    presentation = f'<p:presentation xmlns:a="{A}" xmlns:r="{R}" xmlns:p="{P}"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>'
    for i in range(7):
        presentation += f'<p:sldId id="{256+i}" r:id="rId{i+2}"/>'
    presentation += f'</p:sldIdLst><p:sldSz cx="{SW}" cy="{SH}" type="screen16x9"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>'
    content = f'<Types xmlns="{CT}"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
    for i in range(1, 8):
        content += f'<Override PartName="/ppt/slides/slide{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
    content += '</Types>'

    with ZipFile(OUT, "w", ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content)
        z.writestr("_rels/.rels", rels([("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument", "ppt/presentation.xml")]))
        z.writestr("ppt/presentation.xml", presentation)
        prels = [("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster", "slideMasters/slideMaster1.xml")]
        prels += [(f"rId{i+2}", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide", f"slides/slide{i+1}.xml") for i in range(7)]
        z.writestr("ppt/_rels/presentation.xml.rels", rels(prels))
        z.writestr("ppt/slideMasters/slideMaster1.xml", master())
        z.writestr("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels([
            ("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout", "../slideLayouts/slideLayout1.xml"),
            ("rId2", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", "../theme/theme1.xml"),
        ]))
        z.writestr("ppt/slideLayouts/slideLayout1.xml", layout())
        z.writestr("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels([("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster", "../slideMasters/slideMaster1.xml")]))
        z.writestr("ppt/theme/theme1.xml", theme())
        z.writestr("ppt/slides/slide1.xml", cover_slide())
        z.writestr("ppt/slides/_rels/slide1.xml.rels", rels([("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout", "../slideLayouts/slideLayout1.xml")]))
        for idx, page in enumerate(PAGES, start=2):
            z.write(OUTDIR / page, f"ppt/media/{page}")
            z.writestr(f"ppt/slides/slide{idx}.xml", image_slide("rId2", page))
            z.writestr(f"ppt/slides/_rels/slide{idx}.xml.rels", rels([
                ("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout", "../slideLayouts/slideLayout1.xml"),
                ("rId2", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image", f"../media/{page}"),
            ]))
    # Fast structural validation of every XML part and all expected slides/assets.
    with ZipFile(OUT) as z:
        names = z.namelist()
        for name in names:
            if name.endswith((".xml", ".rels")):
                ET.fromstring(z.read(name))
        assert len([n for n in names if n.startswith("ppt/slides/slide") and n.endswith(".xml")]) == 7
        assert len([n for n in names if n.startswith("ppt/media/") and n.endswith(".png")]) == 6
    print(f"Created and structurally verified {OUT} ({OUT.stat().st_size:,} bytes; 7 slides, 6 diagrams).")

if __name__ == "__main__":
    main()
