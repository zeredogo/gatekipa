import os
from PIL import Image

src_dir = "/Users/mac/Gatekipa/screenshots"
out_dir_iphone = "/Users/mac/Gatekipa/screenshots/clean_iphone"
out_dir_ipad = "/Users/mac/Gatekipa/screenshots/clean_ipad"

os.makedirs(out_dir_iphone, exist_ok=True)
os.makedirs(out_dir_ipad, exist_ok=True)

def process_image(img, target_size, out_path):
    target_width, target_height = target_size
    
    # Calculate aspect ratios
    img_ratio = img.width / img.height
    target_ratio = target_width / target_height
    
    if img_ratio > target_ratio:
        # Image is wider than target. Scale based on width.
        new_width = target_width
        new_height = int(target_width / img_ratio)
    else:
        # Image is taller than target. Scale based on height.
        new_height = target_height
        new_width = int(target_height * img_ratio)
        
    resized_img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
    
    # Get a background color from the edge of the image to make padding look seamless
    # Sample from the middle-left edge
    bg_color = img.getpixel((5, img.height // 2))
    
    # Create the canvas
    canvas = Image.new("RGB", target_size, bg_color)
    
    # Paste centered
    offset_x = (target_width - new_width) // 2
    offset_y = (target_height - new_height) // 2
    canvas.paste(resized_img, (offset_x, offset_y))
    
    canvas.save(out_path, "PNG")

for filename in os.listdir(src_dir):
    if filename.endswith(".jpeg"):
        filepath = os.path.join(src_dir, filename)
        img = Image.open(filepath).convert("RGB")
        
        # Crop the image to remove the top 85px (Android Status Bar) 
        # and bottom 140px (Android Navigation Bar)
        cropped_img = img.crop((0, 85, img.width, img.height - 140))
        
        name = os.path.splitext(filename)[0]
        
        # 1. iPhone size: 1242x2688
        process_image(cropped_img, (1242, 2688), os.path.join(out_dir_iphone, f"{name}.png"))
        
        # 2. iPad size: 2048x2732
        process_image(cropped_img, (2048, 2732), os.path.join(out_dir_ipad, f"{name}.png"))

print("Done generating non-stretched images")
