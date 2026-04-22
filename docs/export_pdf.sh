#!/bin/bash
# =============================================================================
# Task 4: Export Final Report to PDF
# =============================================================================
# Converts docs/final_report.md → docs/final_report.pdf using pandoc.
# Supports: images, tables, code blocks, UTF-8 Vietnamese text.
# Mermaid diagrams require mmdc (mermaid-cli) for pre-processing.
#
# Usage: bash docs/export_pdf.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT="$SCRIPT_DIR/final_report.md"
PDF_OUT="$SCRIPT_DIR/final_report.pdf"
IMG_DIR="$SCRIPT_DIR/images"

echo "============================================================"
echo "  Export Final Report → PDF"
echo "============================================================"

# ─── Check dependencies ─────────────────────────────────────────
check_tool() {
    if command -v "$1" &>/dev/null; then
        echo "  ✅ $1 found"
        return 0
    else
        echo "  ❌ $1 not found"
        return 1
    fi
}

echo ""
echo "[1/4] Checking dependencies..."
PANDOC_OK=0
check_tool pandoc && PANDOC_OK=1

if [ "$PANDOC_OK" -eq 0 ]; then
    echo ""
    echo "  pandoc is required. Install with:"
    echo "    sudo apt install pandoc texlive-xetex texlive-fonts-recommended"
    echo ""
    echo "  Or use a simpler method (see below)..."
fi

# Check LaTeX engine
LATEX_OK=0
check_tool xelatex && LATEX_OK=1 || check_tool pdflatex && LATEX_OK=1 || true

# ─── Pre-process: Convert Mermaid to images ─────────────────────
echo ""
echo "[2/4] Checking for Mermaid diagrams..."

MERMAID_COUNT=$(grep -c '```mermaid' "$REPORT" 2>/dev/null || true)
if [ "$MERMAID_COUNT" -gt 0 ]; then
    echo "  Found $MERMAID_COUNT Mermaid diagram(s)"
    
    if command -v mmdc &>/dev/null; then
        echo "  Pre-processing Mermaid → PNG..."
        # Extract mermaid blocks and convert
        TEMP_REPORT="$SCRIPT_DIR/.final_report_processed.md"
        cp "$REPORT" "$TEMP_REPORT"
        
        IDX=0
        while grep -q '```mermaid' "$TEMP_REPORT"; do
            IDX=$((IDX+1))
            MMD_FILE="/tmp/mermaid_$IDX.mmd"
            PNG_FILE="$IMG_DIR/mermaid_$IDX.png"
            
            # Extract first mermaid block
            sed -n '/```mermaid/,/```/{/```mermaid/d;/```/d;p}' "$TEMP_REPORT" | head -50 > "$MMD_FILE"
            
            # Convert to PNG
            mmdc -i "$MMD_FILE" -o "$PNG_FILE" -w 1200 -b transparent 2>/dev/null
            
            # Replace mermaid block with image reference
            sed -i "0,/\`\`\`mermaid/{ /\`\`\`mermaid/,/\`\`\`/c\\\\![Diagram $IDX](images/mermaid_$IDX.png) }" "$TEMP_REPORT"
            
            rm -f "$MMD_FILE"
            echo "    ✅ Mermaid diagram $IDX → mermaid_$IDX.png"
        done
        REPORT="$TEMP_REPORT"
    else
        echo "  ⚠️  mmdc (mermaid-cli) not found"
        echo "  Mermaid diagrams will appear as code blocks in PDF"
        echo "  Install: npm install -g @mermaid-js/mermaid-cli"
    fi
else
    echo "  No Mermaid diagrams found"
fi

# ─── Verify images ──────────────────────────────────────────────
echo ""
echo "[3/4] Verifying images..."
IMG_COUNT=$(ls -1 "$IMG_DIR"/*.png 2>/dev/null | wc -l)
echo "  Found $IMG_COUNT PNG images in $IMG_DIR"

# Check that all referenced images exist
MISSING=0
grep -oP 'images/[^)]+\.png' "$REPORT" 2>/dev/null | sort -u | while read img; do
    FULL="$SCRIPT_DIR/$img"
    if [ -f "$FULL" ]; then
        echo "    ✅ $img"
    else
        echo "    ❌ $img MISSING"
        MISSING=$((MISSING+1))
    fi
done

# ─── Generate PDF ───────────────────────────────────────────────
echo ""
echo "[4/4] Generating PDF..."

if [ "$PANDOC_OK" -eq 1 ] && [ "$LATEX_OK" -eq 1 ]; then
    # Full pandoc + xelatex (best quality, Vietnamese support)
    echo "  Using pandoc + xelatex..."
    cd "$SCRIPT_DIR"
    pandoc "$REPORT" \
        -o "$PDF_OUT" \
        --pdf-engine=xelatex \
        -V geometry:margin=2.5cm \
        -V fontsize=11pt \
        -V mainfont="DejaVu Sans" \
        -V monofont="DejaVu Sans Mono" \
        -V CJKmainfont="Noto Sans CJK" \
        -V colorlinks=true \
        -V linkcolor=blue \
        --highlight-style=tango \
        --toc \
        --toc-depth=3 \
        -f markdown+pipe_tables+fenced_code_blocks+backtick_code_blocks \
        --resource-path="$SCRIPT_DIR" \
        2>&1
    
    if [ -f "$PDF_OUT" ]; then
        SIZE=$(du -h "$PDF_OUT" | cut -f1)
        echo "  ✅ Created: $PDF_OUT ($SIZE)"
    else
        echo "  ❌ PDF generation failed"
    fi

elif [ "$PANDOC_OK" -eq 1 ]; then
    # pandoc without LaTeX – try HTML intermediate
    echo "  Using pandoc → HTML → PDF (no LaTeX)..."
    cd "$SCRIPT_DIR"
    
    HTML_OUT="$SCRIPT_DIR/final_report.html"
    pandoc "$REPORT" \
        -o "$HTML_OUT" \
        --self-contained \
        --css=/dev/null \
        --metadata title="Báo cáo đồ án cuối kỳ - CE2024" \
        --toc \
        -f markdown+pipe_tables+fenced_code_blocks \
        --resource-path="$SCRIPT_DIR" \
        2>&1
    
    if [ -f "$HTML_OUT" ]; then
        SIZE=$(du -h "$HTML_OUT" | cut -f1)
        echo "  ✅ Created HTML: $HTML_OUT ($SIZE)"
        echo "  💡 Open in browser and Print → PDF"
        
        # Try wkhtmltopdf if available
        if command -v wkhtmltopdf &>/dev/null; then
            wkhtmltopdf --enable-local-file-access "$HTML_OUT" "$PDF_OUT" 2>/dev/null
            echo "  ✅ Created PDF: $PDF_OUT"
        fi
    fi

else
    echo "  ❌ pandoc not available"
    echo ""
    echo "  ══════════════════════════════════════════════"
    echo "  Alternative methods to generate PDF:"
    echo "  ══════════════════════════════════════════════"
    echo ""
    echo "  Method 1 – Install pandoc:"
    echo "    sudo apt install pandoc texlive-xetex texlive-fonts-recommended"
    echo "    bash docs/export_pdf.sh"
    echo ""
    echo "  Method 2 – VS Code:"
    echo "    1. Open docs/final_report.md in VS Code"
    echo "    2. Install 'Markdown PDF' extension"
    echo "    3. Ctrl+Shift+P → 'Markdown PDF: Export (pdf)'"
    echo ""
    echo "  Method 3 – Online converter:"
    echo "    1. Go to https://md2pdf.netlify.app/"
    echo "    2. Paste report content"
    echo "    3. Download PDF"
    echo ""
    echo "  Method 4 – Python (grip + weasyprint):"
    echo "    pip install grip weasyprint"
    echo "    grip docs/final_report.md --export docs/final_report.html"
    echo "    weasyprint docs/final_report.html docs/final_report.pdf"
    echo "  ══════════════════════════════════════════════"
fi

# Cleanup
rm -f "$SCRIPT_DIR/.final_report_processed.md"

echo ""
echo "============================================================"
echo "  Final deliverables:"
echo "============================================================"
echo "  docs/"
ls -1 "$SCRIPT_DIR" | grep -E "\.(md|pdf|html)$" | while read f; do
    SIZE=$(du -h "$SCRIPT_DIR/$f" | cut -f1)
    echo "  ├── $f  ($SIZE)"
done
echo "  └── images/"
ls -1 "$IMG_DIR"/*.png 2>/dev/null | while read f; do
    SIZE=$(du -h "$f" | cut -f1)
    echo "      ├── $(basename $f)  ($SIZE)"
done
echo "============================================================"
