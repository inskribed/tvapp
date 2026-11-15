"""Renders the Orka logo assets (PNG) from mark.py. Needs python3 + node with playwright.
Run from this folder, then copy into app/src/main/res (see CLAUDE.md)."""
import os, mark, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
INTER = os.path.normpath(os.path.join(HERE, "../../app/src/main/res/font/inter_bold.ttf"))
BG = "#0B0B0F"
def page(inner, w, h, bg):
    return f'''<html><head><style>@font-face{{font-family:Inter;src:url("file://{INTER}");font-weight:700}}
html,body{{margin:0;background:{bg}}}svg{{display:block}}</style></head><body>{inner}</body></html>'''
def render(name, inner, w, h, bg="transparent"):
    open(f"{name}.html","w").write(page(inner, w, h, bg))
    js = f"""const {{chromium}}=require('playwright');(async()=>{{const b=await chromium.launch();const p=await b.newPage({{viewport:{{width:{w},height:{h}}}}});
await p.goto('file://'+process.cwd()+'/{name}.html');await p.evaluate(()=>document.fonts.ready);await p.screenshot({{path:'{name}.png',omitBackground:{str(bg=='transparent').lower()}}});await b.close();}})();"""
    open(f"r_{name}.js","w").write(js); subprocess.run(["node", f"r_{name}.js"], check=True)

# 1) in-app mark, transparent (cropped to the logo)
render("orka_mark", f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="288" viewBox="120 50 320 360">{mark.mark_svg("a")}</svg>', 256, 288)
# 2) adaptive icon foreground 432x432 (mark inside the 264px safe zone)
render("ic_launcher_foreground", f'<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 432 432"><g transform="translate(216 216) scale(0.74) translate(-285 -229)">{mark.mark_svg("b")}</g></svg>', 432, 432)
# 3) TV banner 640x360 (xhdpi) and 960x540 (xxhdpi)
def banner(w, h):
    k = w / 640
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 640 360">
<defs><radialGradient id="bg" cx="0.22" cy="0.5" r="0.7"><stop offset="0" stop-color="#0E3B3A"/><stop offset="1" stop-color="{BG}"/></radialGradient></defs>
<rect width="640" height="360" fill="url(#bg)"/>
<g transform="translate(97 62) scale(0.58) translate(-120 -50)">{mark.mark_svg("c")}</g>
<text x="299" y="214" font-family="Inter" font-weight="700" font-size="104" fill="#F2F2F5" letter-spacing="-2">Orka</text>
</svg>'''
render("banner_xhdpi", banner(640, 360), 640, 360, BG)
render("banner_xxhdpi", banner(960, 540), 960, 540, BG)
# preview on a dark launcher-style tile
render("preview", f'''<svg xmlns="http://www.w3.org/2000/svg" width="720" height="260" viewBox="0 0 720 260"><rect width="720" height="260" fill="#0B0B0F"/>
<rect x="30" y="30" width="200" height="200" rx="44" fill="#14141B"/><g transform="translate(130 130) scale(0.36) translate(-285 -229)">{mark.mark_svg("d")}</g>
<circle cx="330" cy="130" r="80" fill="#14141B"/><g transform="translate(330 130) scale(0.3) translate(-285 -229)">{mark.mark_svg("e")}</g>
<g transform="translate(470 80) scale(0.18) translate(-120 -50)">{mark.mark_svg("f")}</g>
<text x="540" y="140" font-family="Inter" font-weight="700" font-size="44" fill="#F2F2F5">Orka</text></svg>''', 720, 260, BG)
