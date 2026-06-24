import os
from PIL import Image, ImageDraw

src_dir = "/Users/mac/Gatekipa/screenshots"
out_dir_iphone = "/Users/mac/Gatekipa/screenshots/clean_iphone"
out_dir_ipad = "/Users/mac/Gatekipa/screenshots/clean_ipad"

os.makedirs(out_dir_iphone, exist_ok=True)
os.makedirs(out_dir_ipad, exist_ok=True)

for filename in os.listdir(src_dir):
    if filename.endswith(".jpeg"):
        filepath = os.path.join(src_dir, filename)
        img = Image.open(filepath).convert("RGB")
        
        # Crop the image to remove the top 85px (Android Status Bar) 
        # and bottom 140px (Android Navigation Bar)
        # Bounding box is (left, upper, right, lower)
        cropped_img = img.crop((0, 85, img.width, img.height - 140))
        
        name = os.path.splitext(filename)[0]
        
        # 1. Generate iPhone size: 1242x2688
        img_iphone = cropped_img.resize((1242, 2688), Image.Resampling.LANCZOS)
        img_iphone.save(os.path.join(out_dir_iphone, f"{name}.png"), "PNG")
        
        # 2. Generate iPad size: 2048x2732
        # Calculate aspect-ratio-preserving width for height=2732
        # cropped_img.height is 1055, cropped_img.width is 591
        new_width = int(cropped_img.width * (2732 / cropped_img.height))
        img_ipad_temp = cropped_img.resize((new_width, 2732), Image.Resampling.LANCZOS)
        
        # Create a white background 2048x2732
        img_ipad = Image.new("RGB", (2048, 2732), (255, 255, 255))
        # Paste the resized image in the center
        offset = ((2048 - new_width) // 2, 0)
        img_ipad.paste(img_ipad_temp, offset)
        img_ipad.save(os.path.join(out_dir_ipad, f"{name}.png"), "PNG")

print("Done cropping UI")
