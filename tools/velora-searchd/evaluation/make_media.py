"""Create synthetic OCR, visual and video fixtures; never reads personal media."""
import argparse
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont


def make(destination):
    destination.mkdir(parents=True, exist_ok=True)
    font = ImageFont.load_default(size=32)
    for name in ("red", "blue", "green"):
        image = Image.new("RGB", (640, 480), "white")
        draw = ImageDraw.Draw(image)
        if name == "red":
            draw.ellipse((150, 50, 490, 390), fill="red")
            draw.text((125, 425), "GRADIENT DESCENT", fill="black", font=font)
        elif name == "blue":
            draw.rectangle((150, 50, 490, 390), fill="blue")
        else:
            draw.polygon([(320, 40), (120, 400), (520, 400)], fill="green")
        image.save(destination / f"{name}.png")
    # All paths in the concat file are fixed, independent of the destination's spelling.
    (destination / "frames.txt").write_text("file 'red.png'\nduration 10\nfile 'blue.png'\nduration 10\nfile 'green.png'\nduration 5\nfile 'green.png'\n")
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "concat", "-safe", "1",
                    "-i", "frames.txt", "-vf", "fps=1", "-t", "25", "-pix_fmt", "yuv420p", "shapes.mp4"],
                   cwd=destination, check=True)
    project = destination / "Course"
    project.mkdir(exist_ok=True)
    (project / "notes.md").write_text(("Deep learning course. Training neural networks with gradient descent, backpropagation, PyTorch and convolutional networks.\n") * 30)
    (project / "pyproject.toml").write_text("[project]\nname='deep-learning-course'\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    make(parser.parse_args().destination.resolve())
