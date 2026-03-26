import os
from PIL import Image, ImageDraw

_script_dir = os.path.dirname(os.path.abspath(__file__))
_project_dir = os.path.dirname(_script_dir)

src = Image.open(os.path.join(_project_dir, 'Resources', 'icon_tent2_1_4.png')).convert('RGBA')

# Crop inward to remove the original rounded rect border/shadow
# The generated icon has ~60px of border/shadow on a 1024px image
inset = 110
src = src.crop((inset, inset, 1024 - inset, 1024 - inset))

# Resize to final size
size = 512
src = src.resize((size, size), Image.LANCZOS)

# Apple squircle mask
radius = int(size * 0.2237)

mask = Image.new('L', (size, size), 0)
draw = ImageDraw.Draw(mask)
draw.rounded_rectangle([(0, 0), (size-1, size-1)], radius=radius, fill=255)

output = Image.new('RGBA', (size, size), (0, 0, 0, 0))
output.paste(src, (0, 0))
output.putalpha(mask)

output.save(os.path.join(_project_dir, 'Resources', 'AppIcon_squircle.png'))
print('Done: cropped + squircle applied')
