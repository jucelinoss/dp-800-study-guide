import os
import re
import sys
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import subprocess

# File configuration
BASE_DIR = Path(__file__).resolve().parent.parent

def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate DOCX from Markdown with rendered callout images"
    )
    parser.add_argument(
        "--locale",
        default="en",
        help="Locale for input/output paths and document language (default: en)"
    )
    parser.add_argument(
        "--input",
        type=str,
        default=None,
        help="Override input markdown file path (relative to repo root)"
    )
    parser.add_argument(
        "--output-md",
        type=str,
        default=None,
        help="Override output v2 markdown file path (relative to repo root)"
    )
    parser.add_argument(
        "--output-docx",
        type=str,
        default=None,
        help="Override output DOCX file path (relative to repo root)"
    )
    return parser.parse_args()


def build_paths(locale, input_override, output_md_override, output_docx_override):
    """Build input/output paths based on locale or overrides."""
    if input_override:
        input_file = BASE_DIR / input_override
    else:
        input_file = (
            BASE_DIR / "i18n" / locale / "certification"
            / "01-database-objects" / "02-specialized-tables.md"
        )

    if output_md_override:
        output_md = BASE_DIR / output_md_override
    else:
        output_md = (
            BASE_DIR / "i18n" / locale / "certification"
            / "01-database-objects" / "02-specialized-tables-v2.md"
        )

    if output_docx_override:
        output_docx = BASE_DIR / output_docx_override
    else:
        output_docx = (
            BASE_DIR / "i18n" / locale / "certification"
            / "01-database-objects" / "02-specialized-tables-v2.docx"
        )

    images_dir = BASE_DIR / "dist" / "images"
    images_dir.mkdir(parents=True, exist_ok=True)

    return input_file, output_md, output_docx, images_dir


# Callout style definitions
CALLOUT_STYLES = {
    "tip": {
        "border_color": (46, 204, 113),  # Green
        "bg_color": (244, 253, 247),
        "text_color": (44, 62, 80),
        "icon": "💡",
        "default_title": "Tip"
    },
    "important": {
        "border_color": (230, 126, 34),  # Orange
        "bg_color": (253, 246, 240),
        "text_color": (44, 62, 80),
        "icon": "🎯",
        "default_title": "Important"
    },
    "warning": {
        "border_color": (241, 196, 15),  # Yellow
        "bg_color": (254, 252, 240),
        "text_color": (44, 62, 80),
        "icon": "⚠️",
        "default_title": "Warning"
    },
    "abstract": {
        "border_color": (52, 152, 219),  # Blue
        "bg_color": (240, 248, 255),
        "text_color": (44, 62, 80),
        "icon": "📝",
        "default_title": "Abstract"
    },
    "note": {
        "border_color": (52, 152, 219),  # Blue
        "bg_color": (240, 248, 255),
        "text_color": (44, 62, 80),
        "icon": "ℹ️",
        "default_title": "Note"
    },
    "success": {
        "border_color": (46, 204, 113),  # Green
        "bg_color": (244, 253, 247),
        "text_color": (44, 62, 80),
        "icon": "✅",
        "default_title": "Answer"
    },
    "caution": {
        "border_color": (231, 76, 60),  # Red
        "bg_color": (253, 242, 242),
        "text_color": (44, 62, 80),
        "icon": "🛑",
        "default_title": "Caution"
    }
}


def load_fonts():
    # Try to load Arial, fall back to default font
    font_paths = [
        "C:\\Windows\\Fonts\\arial.ttf",
        "C:\\Windows\\Fonts\\segoeui.ttf",
        "arial.ttf"
    ]
    font_bold_paths = [
        "C:\\Windows\\Fonts\\arialbd.ttf",
        "C:\\Windows\\Fonts\\segoeuib.ttf",
        "arialbd.ttf"
    ]

    font_body = None
    font_title = None

    for path in font_paths:
        try:
            font_body = ImageFont.truetype(path, 16)
            break
        except IOError:
            continue

    for path in font_bold_paths:
        try:
            font_title = ImageFont.truetype(path, 18)
            break
        except IOError:
            continue

    if not font_body:
        font_body = ImageFont.load_default()
    if not font_title:
        font_title = ImageFont.load_default()

    return font_title, font_body


def render_callout_image(kind, title, lines, output_path):
    style = CALLOUT_STYLES.get(kind.lower(), CALLOUT_STYLES["note"])
    font_title, font_body = load_fonts()

    # Prepare full text for measuring and line wrapping
    # Maximum image box width
    max_width = 800
    padding_left = 30
    padding_right = 20
    padding_top = 20
    padding_bottom = 20
    border_width = 6

    draw_test = ImageDraw.Draw(Image.new("RGB", (1, 1)))

    # Process text lines and wrap those exceeding the width
    text_max_w = max_width - padding_left - padding_right - border_width

    formatted_lines = []

    # Title (with icon)
    display_title = f"{style['icon']} {title or style['default_title']}"

    # Wrap body text lines
    for line in lines:
        line = line.strip()
        # Skip empty lines
        if not line:
            formatted_lines.append("")
            continue

        # Simple word wrapping to fit width
        words = line.split(" ")
        current_line = ""
        for word in words:
            test_line = f"{current_line} {word}".strip()
            # Measure test line width
            bbox = draw_test.textbbox((0, 0), test_line, font=font_body)
            w = bbox[2] - bbox[0]
            if w <= text_max_w:
                current_line = test_line
            else:
                formatted_lines.append(current_line)
                current_line = word
        if current_line:
            formatted_lines.append(current_line)

    # Measure required height
    # Title height
    title_bbox = draw_test.textbbox((0, 0), display_title, font=font_title)
    title_height = title_bbox[3] - title_bbox[0] + 10  # Extra margin below title

    # Body line height
    line_height = 24  # Approximate height per text line with spacing
    body_height = len(formatted_lines) * line_height

    total_height = padding_top + title_height + body_height + padding_bottom

    # Create the final image
    img = Image.new("RGB", (max_width, total_height), style["bg_color"])
    draw = ImageDraw.Draw(img)

    # Draw left border
    draw.rectangle(
        [(0, 0), (border_width, total_height)],
        fill=style["border_color"]
    )

    # Draw title
    x_pos = padding_left + border_width
    y_pos = padding_top
    draw.text((x_pos, y_pos), display_title, fill=style["border_color"], font=font_title)

    # Draw body
    y_pos += title_height
    for line in formatted_lines:
        draw.text((x_pos, y_pos), line, fill=style["text_color"], font=font_body)
        y_pos += line_height

    img.save(output_path)
    print(f"Generated: {output_path}")


def parse_and_convert_markdown(input_file, output_md, images_dir):
    content = input_file.read_text(encoding="utf-8")

    # Find callouts
    # Pattern: > [!kind] or > [!kind]- Title
    # Followed by lines starting with >
    lines = content.splitlines()
    new_lines = []

    i = 0
    callout_count = 0
    while i < len(lines):
        line = lines[i]
        match = re.match(r"^>\s*\[!([a-zA-Z0-9_-]+)\](?:-?\s*(.*))?$", line.strip())
        if match:
            kind = match.group(1).strip()
            title = (match.group(2) or "").strip()

            # Collect callout content
            callout_lines = []
            i += 1
            while i < len(lines) and lines[i].strip().startswith(">"):
                # Remove leading "> "
                body_line = lines[i].strip()
                if body_line.startswith(">"):
                    body_line = body_line[1:].strip()
                callout_lines.append(body_line)
                i += 1

            # Generate image for the callout
            image_name = f"callout_table_{callout_count}.png"
            image_path = images_dir / image_name

            render_callout_image(kind, title, callout_lines, image_path)

            # Add image tag to markdown
            new_lines.append(f"\n\n![](../../../../dist/images/{image_name})\n\n")
            callout_count += 1
        else:
            new_lines.append(line)
            i += 1

    # Write v2.md
    output_content = "\n".join(new_lines)
    output_md.write_text(output_content, encoding="utf-8")
    print(f"MD v2 file created with callout images: {output_md}")


def generate_docx(output_md, output_docx, locale):
    print("Converting MD v2 to DOCX...")
    cmd = [
        "pandoc",
        str(output_md),
        "-o", str(output_docx),
        "--from", "markdown+pipe_tables+fenced_code_blocks+backtick_code_blocks+definition_lists",
        "--to", "docx",
        "--highlight-style", "tango",
        "-V", f"lang={locale}",
        "--standalone"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        print(f"Success! DOCX file generated at: {output_docx}")
    else:
        print(f"Pandoc error: {result.stderr}")
        sys.exit(1)


if __name__ == "__main__":
    args = parse_args()
    input_file, output_md, output_docx, images_dir = build_paths(
        args.locale, args.input, args.output_md, args.output_docx
    )
    parse_and_convert_markdown(input_file, output_md, images_dir)
    generate_docx(output_md, output_docx, args.locale)
