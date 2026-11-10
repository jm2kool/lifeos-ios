"""Cuts the 20-second vertical Matinee promo from the simulator clips in the matinee-promo release.

    python3 promo/make_ad.py <clips dir> <work dir> <out.mp4>

Each scene was recorded in slow motion (pace.txt), so it is sped back up here and resampled to a steady
60 fps. The phone sits on a blurred copy of its own screen, so each film's colour fills the whole frame.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import assets  # noqa: E402

CLIPS, WORK, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(WORK, exist_ok=True)
PACE = float(open(os.path.join(CLIPS, "pace.txt")).read().split("=")[1])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DUNE, SPIDER, DIAL, BB, BLUE = (255, 178, 120), (255, 128, 150), (120, 232, 200), (178, 226, 112), (140, 178, 255)

# clip, start and end in the raw recording (seconds), speed-up, headline, small line, small-line colour
SEGMENTS = [
    ("splash", 4.55, 5.75, 1, "", "", None),
    ("film", 5.2, 9.6, PACE, "The logo lifts off the poster.", "Textless art, real title logos", DUNE),
    ("film", 9.6, 13.6, PACE, "The page takes its colour.", "Scroll, and the logo pins up top", DUNE),
    ("colour", 8.0, 13.6, PACE, "Every film, its own colour.", "The accent follows through", SPIDER),
    ("film", 16.6, 25.6, PACE, "Rate it 1–100.", "Not just five stars", DIAL),
    ("show", 9.2, 12.2, PACE, "TV shows, too.", "Every episode, ticked and scored", BB),
    ("show", 23.6, 31.4, PACE, "TV shows, too.", "Every episode, ticked and scored", BB),
    ("story", 12.6, 22.2, PACE, "Your review, on your Story.", "One tap to Instagram Stories", DUNE),
    ("stats", 10.2, 12.0, 1, "Your year, in numbers.", "52 films · 5 days 12 hours · avg 89", BLUE),
]
END_SECONDS = 2.5


def run(cmd):
    subprocess.run(cmd, check=True)


def segment(i, clip, start, end, speed, line1, line2, colour):
    out = os.path.join(WORK, f"seg{i:02d}.mp4")
    dur = (end - start) / speed
    cap = os.path.join(WORK, f"cap{i:02d}.png")
    if line1:
        assets.caption(cap, line1, line2, colour or (255, 255, 255))
    else:
        from PIL import Image
        Image.new("RGBA", (assets.W, 300), (0, 0, 0, 0)).save(cap)
    # Captions fade in only when the headline changes.
    fade = "fade=in:st=0:d=0.25:alpha=1," if i == 0 or SEGMENTS[i - 1][4] != line1 else ""
    sw, sh, sx, sy = assets.SW, assets.SH, assets.SX, assets.SY
    graph = (
        f"[0:v]trim=start={start}:end={end},setpts=(PTS-STARTPTS)/{speed},fps=60,format=yuv444p,split[a][b];"
        f"[a]scale=1080:2348,crop=1080:1920,gblur=sigma=60,eq=brightness=-0.16:saturation=1.6,format=rgba[bg];"
        f"[b]scale={sw}:{sh}:flags=lanczos,format=rgba[fg0];[1:v]format=gray[m];[fg0][m]alphamerge[fg];"
        f"[bg][fg]overlay={sx}:{sy}[c1];[c1][2:v]overlay=0:0[c2];"
        f"[3:v]format=rgba,{fade}null[cap];[c2][cap]overlay=0:0,format=yuv420p[out]"
    )
    run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(CLIPS, f"{clip}.mp4"),
         "-loop", "1", "-framerate", "60", "-i", os.path.join(WORK, "mask.png"),
         "-loop", "1", "-framerate", "60", "-i", os.path.join(WORK, "bezel.png"),
         "-loop", "1", "-framerate", "60", "-i", cap,
         "-filter_complex", graph, "-map", "[out]", "-t", f"{dur:.4f}", "-r", "60",
         "-c:v", "libx264", "-preset", "slow", "-crf", "15", "-pix_fmt", "yuv420p", out])
    return out, dur


def endcard(i):
    out = os.path.join(WORK, f"seg{i:02d}.mp4")
    run(["ffmpeg", "-v", "error", "-y", "-loop", "1", "-framerate", "60", "-i", os.path.join(WORK, "end.png"),
         "-vf", "fade=in:st=0:d=0.4,format=yuv420p", "-t", str(END_SECONDS), "-r", "60",
         "-c:v", "libx264", "-preset", "slow", "-crf", "15", out])
    return out, END_SECONDS


def main():
    assets.mask(os.path.join(WORK, "mask.png"))
    assets.bezel(os.path.join(WORK, "bezel.png"))
    assets.endcard(os.path.join(WORK, "end.png"), os.path.join(ROOT, "Matinee/Assets.xcassets/AppIcon.appiconset/icon-1024.png"))
    parts = [segment(i, *s) for i, s in enumerate(SEGMENTS)]
    parts.append(endcard(len(SEGMENTS)))
    total = sum(d for _, d in parts)
    print(f"total {total:.2f}s")
    listing = os.path.join(WORK, "parts.txt")
    with open(listing, "w") as f:
        f.writelines(f"file '{p}'\n" for p, _ in parts)
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing,
         "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
         "-map", "0:v", "-map", "1:a", "-shortest", "-r", "60",
         "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-profile:v", "high", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", OUT])


main()
