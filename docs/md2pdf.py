#!/usr/bin/env python3
"""
Convert final_report.md → final_report.pdf
Uses Python markdown + weasyprint (no pandoc/LaTeX needed)
Supports: images, tables, code blocks, Vietnamese text

Usage: python3 docs/md2pdf.py
"""

import os
import sys
import re

try:
    import markdown
    from weasyprint import HTML, CSS
except ImportError:
    print("Installing dependencies...")
    os.system(f"{sys.executable} -m pip install --user --break-system-packages markdown weasyprint")
    import markdown
    from weasyprint import HTML, CSS

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MD_FILE = os.path.join(SCRIPT_DIR, "final_report.md")
HTML_FILE = os.path.join(SCRIPT_DIR, "final_report.html")
PDF_FILE = os.path.join(SCRIPT_DIR, "final_report.pdf")

# ─── CSS for professional report styling ─────────────────────────
REPORT_CSS = """
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=JetBrains+Mono:wght@400;500&display=swap');

@page {
    size: A4;
    margin: 2.5cm 2cm;
    @bottom-center {
        content: counter(page);
        font-size: 9pt;
        color: #666;
    }
}

body {
    font-family: 'Inter', 'Segoe UI', 'Noto Sans', Arial, sans-serif;
    font-size: 11pt;
    line-height: 1.6;
    color: #1a1a2e;
    max-width: 100%;
}

h1 {
    font-size: 22pt;
    font-weight: 700;
    color: #0f3460;
    border-bottom: 3px solid #0f3460;
    padding-bottom: 8px;
    margin-top: 40px;
    page-break-before: always;
}

h1:first-of-type {
    page-break-before: avoid;
    text-align: center;
    font-size: 26pt;
}

h2 {
    font-size: 16pt;
    font-weight: 600;
    color: #16213e;
    border-bottom: 1.5px solid #e0e0e0;
    padding-bottom: 4px;
    margin-top: 30px;
}

h3 {
    font-size: 13pt;
    font-weight: 600;
    color: #1a3c6e;
    margin-top: 20px;
}

h4 {
    font-size: 11pt;
    font-weight: 600;
    color: #2d5e8a;
}

/* Tables */
table {
    width: 100%;
    border-collapse: collapse;
    margin: 15px 0;
    font-size: 10pt;
    page-break-inside: avoid;
}

th {
    background-color: #0f3460;
    color: white;
    font-weight: 600;
    text-align: left;
    padding: 8px 10px;
    border: 1px solid #0a2647;
}

td {
    padding: 6px 10px;
    border: 1px solid #d0d0d0;
    vertical-align: top;
}

tr:nth-child(even) {
    background-color: #f5f7fa;
}

tr:hover {
    background-color: #e8f0fe;
}

/* Code blocks */
code {
    font-family: 'JetBrains Mono', 'Consolas', 'Courier New', monospace;
    font-size: 9pt;
    background-color: #f0f2f5;
    padding: 1px 4px;
    border-radius: 3px;
    color: #c7254e;
}

pre {
    background-color: #1e1e2e;
    color: #cdd6f4;
    padding: 14px 18px;
    border-radius: 6px;
    overflow-x: auto;
    font-size: 9pt;
    line-height: 1.5;
    page-break-inside: avoid;
    border-left: 4px solid #0f3460;
}

pre code {
    background: none;
    color: inherit;
    padding: 0;
    font-size: 9pt;
}

/* Images */
img {
    max-width: 100%;
    height: auto;
    display: block;
    margin: 15px auto;
    border: 1px solid #e0e0e0;
    border-radius: 4px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
}

/* Blockquotes (used for alerts) */
blockquote {
    border-left: 4px solid #0f3460;
    background-color: #f0f4ff;
    padding: 10px 15px;
    margin: 15px 0;
    font-size: 10pt;
    page-break-inside: avoid;
}

blockquote p:first-child {
    font-weight: 600;
}

/* Lists */
ul, ol {
    padding-left: 25px;
}

li {
    margin-bottom: 3px;
}

/* Horizontal rules */
hr {
    border: none;
    border-top: 2px solid #e0e0e0;
    margin: 30px 0;
}

/* Mermaid code blocks → show as styled text */
.mermaid-placeholder {
    background-color: #f8f9fa;
    border: 2px dashed #a0a0c0;
    padding: 15px;
    text-align: center;
    color: #666;
    font-style: italic;
    border-radius: 6px;
}

/* Star ratings in tables */
td:last-child {
    white-space: nowrap;
}

/* Emoji support */
.emoji {
    font-family: 'Noto Color Emoji', 'Apple Color Emoji', sans-serif;
}

/* Print optimization */
@media print {
    h1, h2, h3 {
        page-break-after: avoid;
    }
    table, pre, blockquote, img {
        page-break-inside: avoid;
    }
}
"""


def convert_md_to_pdf():
    print("=" * 60)
    print("  Markdown → PDF Converter")
    print("=" * 60)

    if not os.path.exists(MD_FILE):
        print(f"  ERROR: {MD_FILE} not found")
        sys.exit(1)

    # ─── Read and pre-process markdown ───────────────────────────
    print(f"\n  Reading: {os.path.basename(MD_FILE)}")
    with open(MD_FILE, 'r', encoding='utf-8') as f:
        md_content = f.read()

    # Convert mermaid blocks to styled placeholders
    def mermaid_to_placeholder(match):
        code = match.group(1).strip()
        # Extract state names for a readable summary
        states = re.findall(r'(\w+)\s*-->', code)
        if states:
            summary = " → ".join(dict.fromkeys(states))  # unique, ordered
            return (f'\n<div class="mermaid-placeholder">'
                    f'<strong>FSM State Diagram</strong><br>'
                    f'{summary}</div>\n')
        return (f'\n<div class="mermaid-placeholder">'
                f'<strong>[Diagram – xem trong Markdown viewer]</strong></div>\n')

    md_content = re.sub(
        r'```mermaid\n(.*?)```',
        mermaid_to_placeholder,
        md_content,
        flags=re.DOTALL
    )

    # Convert GitHub-style alerts to blockquotes
    for alert_type in ['NOTE', 'TIP', 'IMPORTANT', 'WARNING', 'CAUTION']:
        md_content = md_content.replace(
            f'> [!{alert_type}]',
            f'> **{alert_type}:**'
        )

    # ─── Convert to HTML ─────────────────────────────────────────
    print("  Converting Markdown → HTML...")
    extensions = ['tables', 'fenced_code', 'codehilite', 'toc', 'nl2br']
    html_body = markdown.markdown(
        md_content,
        extensions=extensions,
        extension_configs={
            'codehilite': {'css_class': 'highlight', 'guess_lang': False},
            'toc': {'toc_depth': 3},
        }
    )

    # Wrap in full HTML document
    html_full = f"""<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="utf-8">
    <title>Báo cáo đồ án cuối kỳ – CE2024 Module 2</title>
</head>
<body>
{html_body}
</body>
</html>"""

    # Save HTML (useful for previewing)
    with open(HTML_FILE, 'w', encoding='utf-8') as f:
        f.write(html_full)
    html_size = os.path.getsize(HTML_FILE) // 1024
    print(f"  ✅ HTML: {os.path.basename(HTML_FILE)} ({html_size}K)")

    # ─── Convert HTML → PDF ──────────────────────────────────────
    print("  Converting HTML → PDF...")
    html_doc = HTML(
        string=html_full,
        base_url=SCRIPT_DIR  # So relative image paths resolve correctly
    )
    css = CSS(string=REPORT_CSS)

    html_doc.write_pdf(PDF_FILE, stylesheets=[css])

    if os.path.exists(PDF_FILE):
        pdf_size = os.path.getsize(PDF_FILE) // 1024
        print(f"  ✅ PDF: {os.path.basename(PDF_FILE)} ({pdf_size}K)")
    else:
        print("  ❌ PDF generation failed")
        sys.exit(1)

    # ─── Summary ─────────────────────────────────────────────────
    print(f"\n{'=' * 60}")
    print("  Output files:")
    print(f"  ├── {os.path.basename(HTML_FILE):30s} ({html_size}K)")
    print(f"  └── {os.path.basename(PDF_FILE):30s} ({pdf_size}K)")
    print(f"\n  ✅ Report is ready for submission!")
    print(f"{'=' * 60}")


if __name__ == '__main__':
    convert_md_to_pdf()
