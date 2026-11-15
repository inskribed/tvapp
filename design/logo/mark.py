import math, sys

TEAL_HI, TEAL_LO = "#1FF2D8", "#00A39A"
LIME, LIME_DEEP = "#C9FF3F", "#8FE02B"

BODY = ("M150,396 Q138,396 138,380 L138,176 C138,160 142,146 156,130 "
        "C176,104 200,80 226,60 C232,90 244,124 270,150 L408,236 Q432,256 408,276 "
        "C330,322 252,372 176,398 Z")

def ribbon(x0, x1, y0, amp, lam, phase, th, step=8):
    top, bot = [], []
    x = x0
    while x <= x1 + 0.1:
        y = y0 + amp * math.sin(2 * math.pi * (x - x0) / lam + phase)
        top.append((x, y - th / 2)); bot.append((x, y + th / 2)); x += step
    pts = top + bot[::-1]
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts) + " Z"

def mark_svg(uid="m"):
    waves = "".join(
        f'<path d="{ribbon(100, 450, y0, 15, 150, ph, 11)}" fill="url(#{uid}w)" opacity="{op}"/>'
        for y0, ph, op in [(296, 0.0, 1.0), (334, 1.3, 0.8), (372, 2.6, 0.6)])
    return f'''<defs>
  <linearGradient id="{uid}b" x1="0.15" y1="0" x2="0.85" y2="1"><stop offset="0" stop-color="{TEAL_HI}"/><stop offset="1" stop-color="{TEAL_LO}"/></linearGradient>
  <radialGradient id="{uid}g" cx="0.02" cy="1.0" r="0.55"><stop offset="0" stop-color="{LIME}" stop-opacity="0.55"/><stop offset="1" stop-color="{LIME}" stop-opacity="0"/></radialGradient>
  <linearGradient id="{uid}w" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="{LIME}"/><stop offset="1" stop-color="{LIME_DEEP}" stop-opacity="0.55"/></linearGradient>
  <clipPath id="{uid}c"><path d="{BODY}"/></clipPath>
</defs>
<path d="{BODY}" fill="url(#{uid}b)"/>
<g clip-path="url(#{uid}c)">
  <rect x="100" y="40" width="360" height="380" fill="url(#{uid}g)"/>
  {waves}
</g>
<path transform="translate(312 204) rotate(24)" d="M0,0 C18,-15 44,-12 60,3 C44,17 18,17 0,0 Z" fill="#F4FFC7" opacity="0.95"/>'''

if __name__ == "__main__":
    open("mark.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">{mark_svg()}</svg>')
