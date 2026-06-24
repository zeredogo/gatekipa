import os
from PIL import Image

src_dir = "/Users/mac/Gatekipa/screenshots"
out_dir_iphone = "/Users/mac/Gatekipa/screenshots/clean_iphone"
out_dir_ipad = "/Users/mac/Gatekipa/screenshots/clean_ipad"

os.makedirs(out_dir_iphone, exist_ok=True)
os.makedirs(out_dir_ipad, exist_ok=True)

for filename in os.listdir(src_dir):
    if filename.endswith(".jpeg"):
        filepath = os.path.join(src_dir, filename)
        img = Image.open(filepath).convert("RGB")
        
        # Get the color of the pixel at (5, 5) to use as fill color
        # Gatekipa seems to have a solid top app bar
        fill_color = img.getpixel((5, 5))
        
        # Draw over the top 85 pixels to hide the Android status bar
        from PIL import ImageDraw
        draw = ImageDraw.Draw(img)
        draw.rectangle([0, 0, img.width, 85], fill=fill_color)
        
        name = os.path.splitext(filename)[0]
        
        # 1. Generate iPhone size: 1242x2688
        img_iphone = img.resize((1242, 2688), Image.Resampling.LANCZOS)
        img_iphone.save(os.path.join(out_dir_iphone, f"{name}.png"), "PNG")
        
        # 2. Generate iPad size: 2048x2732
        # First resize height to 2732 (preserving aspect ratio roughly)
        # width = 591 * (2732/1280) = 1261
        img_ipad_temp = img.resize((1261, 2732), Image.Resampling.LANCZOS)
        # Create a white background 2048x2732
        img_ipad = Image.new("RGB", (2048, 2732), (255, 255, 255))
        # Paste the resized image in the center
        offset = ((2048 - 1261) // 2, 0)
        img_ipad.paste(img_ipad_temp, offset)
        img_ipad.save(os.path.join(out_dir_ipad, f"{name}.png"), "PNG")

print("Done")
