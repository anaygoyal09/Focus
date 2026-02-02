#!/usr/bin/env python3
from PIL import Image, ImageDraw
import os

# Create icon at various sizes
sizes = [16, 32, 64, 128, 256, 512, 1024]
iconset_path = '/Users/anaygoyal/Downloads/Focus/FocusApp/Focus.iconset'
os.makedirs(iconset_path, exist_ok=True)

for size in sizes:
    # Create image with gradient background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Draw circular gradient background (purple to blue)
    center = size // 2
    for i in range(center, 0, -1):
        # Gradient from purple (#8B5CF6) to blue (#3B82F6)
        ratio = i / center
        r = int(139 * ratio + 59 * (1 - ratio))
        g = int(92 * ratio + 130 * (1 - ratio))
        b = int(246 * ratio + 246 * (1 - ratio))
        draw.ellipse([center - i, center - i, center + i, center + i], fill=(r, g, b, 255))
    
    # Draw a simple target/focus circle in the center
    inner_radius = int(size * 0.25)
    draw.ellipse([center - inner_radius, center - inner_radius, 
                  center + inner_radius, center + inner_radius], 
                 outline=(255, 255, 255, 255), width=max(1, size // 32))
    
    # Draw center dot
    dot_radius = int(size * 0.08)
    draw.ellipse([center - dot_radius, center - dot_radius,
                  center + dot_radius, center + dot_radius],
                 fill=(255, 255, 255, 255))
    
    # Draw outer ring
    outer_radius = int(size * 0.4)
    draw.ellipse([center - outer_radius, center - outer_radius,
                  center + outer_radius, center + outer_radius],
                 outline=(255, 255, 255, 200), width=max(1, size // 48))
    
    # Save at 1x
    img.save(f'{iconset_path}/icon_{size}x{size}.png')
    # Save at 2x for retina (except 1024)
    if size <= 512:
        img.save(f'{iconset_path}/icon_{size//2}x{size//2}@2x.png')

print('Icon images created successfully!')
