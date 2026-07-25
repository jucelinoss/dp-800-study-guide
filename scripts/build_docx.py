"""
build_docx.py
=============
Build a DOCX edition of the DP-800 study guide from any supported locale.

Usage:
    python scripts/build_docx.py --locale en
    python scripts/build_docx.py --locale pt-BR
    python scripts/build_docx.py --locale pt-BR --include-resources
"""

import argparse
import os
import re
import sys
import subprocess
from datetime import datetime
from pathlib import Path

BASE_DIR  = Path(__file__).resolve().parent.parent
PT_BR_DIR = BASE_DIR / "i18n" / "pt-BR" / "certification"
EN_DIR    = BASE_DIR / "certification"
DIST_DIR  = BASE_DIR / "dist"

THEORY_SECTIONS = [
    ("01-database-objects",            "Domain 1 — Database Objects"),
    ("02-programmability-objects",     "Domain 2 — Programmability Objects"),
    ("03-advanced-tsql",               "Domain 3 — Advanced T-SQL"),
    ("04-ai-assisted-tools",           "Domain 4 — AI-Assisted Tools"),
    ("05-data-security-compliance",    "Domain 5 — Data Security and Compliance"),
    ("06-performance-optimization",    "Domain 6 — Performance Optimization"),
    ("07-cicd-database-projects",      "Domain 7 — CI/CD Database Projects"),
    ("08-azure-services-integration",  "Domain 8 — Azure Services Integration"),
    ("09-models-embeddings",           "Domain 9 — Models and Embeddings"),
    ("10-intelligent-search",          "Domain 10 — Intelligent Search"),
    ("11-rag",                         "Domain 11 — RAG"),
    ("12-other-topics",                "Domain 12 — Other Topics"),
]

landing_pages = {
    "database-objects.md", "programmability-objects.md",
    "advanced-tsql.md", "ai-assisted-tools.md",
    "data-security-compliance.md", "performance-optimization.md",
    "cicd-database-projects.md", "azure-services-integration.md",
    "models-embeddings.md", "intelligent-search.md", "rag.md",
    "dp-800-overview.md", "cheat-sheets.md", "tsql-code-examples.md",
    "practice-questions.md", "appendix.md", "mock-exam-1.md",
    "mock-exam-2.md", "labs.md",
}

def get_files(directory: Path) -> list[Path]:
    return sorted(
        [f for f in directory.glob("*.md") if f.name not in landing_pages and not f.name.startswith("AUDITORIA")],
        key=lambda p: p.name,
    )

def build_book_manifest(source_dir: Path, include_resources: bool) -> list[tuple[str, str, list[Path]]]:
    res = source_dir / "resources"
    manifest: list[tuple[str, str, list[Path]]] = []

    for folder, label in THEORY_SECTIONS:
        d = source_dir / folder
        if d.is_dir():
            files = get_files(d)
            if files:
                manifest.append(("THEORY", label, files))

    final_review = res / "final-review.md"
    if final_review.exists():
        manifest.append(("FINAL REVIEW", "Final Review", [final_review]))

    if not include_resources:
        return manifest

    cheat_order = ["tsql-core-commands.md", "azure-sql-config-quick-ref.md", "json-functions-quick-ref.md", "security-quick-ref.md", "performance-dmvs-quick-ref.md", "vector-ai-quick-ref.md"]
    cheat_files = [res / "cheat-sheets" / f for f in cheat_order if (res / "cheat-sheets" / f).exists()]
    if cheat_files:
        manifest.append(("QUICK REFERENCE", "Cheat Sheets", cheat_files))

    return manifest

FRONTMATTER_RE = re.compile(r"^---\s*\n.*?\n---\s*\n", re.DOTALL)
CALLOUT_MAP = {
    "abstract":   "[ RESUMO ]", "tip": "[ DICA ]", "note": "[ NOTA ]",
    "important":  "[ IMPORTANTE ]", "warning": "[ AVISO ]", "caution": "[ ATENCAO ]",
    "success":    "[ RESPOSTA ]", "info": "[ INFO ]"
}
CALLOUT_RE = re.compile(r"^> \[!(" + "|".join(CALLOUT_MAP.keys()) + r")\](?:-\s*(.+))?$", re.IGNORECASE | re.MULTILINE)

def strip_frontmatter(content: str) -> str:
    return FRONTMATTER_RE.sub("", content, count=1)

def convert_callouts(content: str) -> str:
    def replace(m: re.Match) -> str:
        kind  = m.group(1).lower()
        title = (m.group(2) or "").strip()
        tag   = CALLOUT_MAP.get(kind, "[ INFO ]")
        return f"> **{tag}** {title}" if title else f"> **{tag}**"
    return CALLOUT_RE.sub(replace, content)

def strip_nav_footer(content: str) -> str:
    lines = content.splitlines()
    cleaned = [line for line in lines if not re.match(r"^\*\*\[.*\]\(.*\).*\*\*\s*$", line)]
    return "\n".join(cleaned)

def resolve_local_links(content: str, source_file: Path) -> str:
    def replace_link(m: re.Match) -> str:
        text = m.group(1)
        url  = m.group(2)
        if url.startswith("http://") or url.startswith("https://"):
            return m.group(0)
        return text
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", replace_link, content)

def process_file(path: Path) -> str:
    content = path.read_text(encoding="utf-8")
    content = strip_frontmatter(content)
    content = convert_callouts(content)
    content = strip_nav_footer(content)
    content = resolve_local_links(content, path)
    return content.strip()

def main():
    parser = argparse.ArgumentParser(description="Build a DOCX edition of the DP-800 study guide.")
    parser.add_argument("--locale", default="en", help="Locale to build; use en for canonical content.")
    parser.add_argument("--include-resources", action="store_true", help="Include translated quick-reference resources when available.")
    parser.add_argument("--output", type=Path, help="Destination DOCX path.")
    args = parser.parse_args()

    source_dir = EN_DIR if args.locale == "en" else BASE_DIR / "i18n" / args.locale / "certification"
    if not source_dir.is_dir():
        parser.error(f"No certification tree exists for locale '{args.locale}': {source_dir}")

    locale_dist = DIST_DIR / args.locale
    locale_dist.mkdir(parents=True, exist_ok=True)
    out_docx = args.output or locale_dist / f"dp-800-study-guide-{args.locale}.docx"
    out_docx.parent.mkdir(parents=True, exist_ok=True)
    out_md = out_docx.with_suffix(".md")
    manifest = build_book_manifest(source_dir, args.include_resources)
    parts: list[str] = []
    current_part = ""
    file_count   = 0

    today = datetime.today().strftime("%Y-%m-%d")
    title_header = f"DP-800 Study Guide ({args.locale})"
    parts.append(f"""% {title_header}
% Microsoft Certified: Fabric Analytics Engineer Associate
% Gerado em {today}

---

This document was generated from `{source_dir.relative_to(BASE_DIR)}`.

\\newpage
""")

    overview = source_dir / "dp-800-overview.md"
    if overview.exists():
        parts.append("# Exam Overview\n\n" + process_file(overview) + "\n\n---\n")

    for (parte, secao_titulo, files) in manifest:
        if parte != current_part:
            current_part = parte
            parts.append(f"\n\n---\n\n# {parte}\n\n---\n")
        parts.append(f"\n## {secao_titulo}\n")
        for md_file in files:
            content = process_file(md_file)
            if content:
                print(f"  [OK] {md_file.relative_to(BASE_DIR)}")
                parts.append(content + "\n\n---\n")
                file_count += 1

    combined = "\n\n".join(parts)
    out_md.write_text(combined, encoding="utf-8")

    size_kb    = out_md.stat().st_size / 1024
    line_count = combined.count("\n")
    print(f"\n[MARKDOWN] {out_md}")
    print(f"           {size_kb:.0f} KB  |  {line_count:,} lines  |  {file_count} files")

    print("\n[PANDOC] Converting to DOCX...")
    ref_docx = DIST_DIR / "reference.docx"
    if not ref_docx.exists():
        subprocess.run(["pandoc", "--print-default-data-file", "reference.docx"], stdout=open(ref_docx, "wb"), stderr=subprocess.DEVNULL)

    cmd = [
        "pandoc", str(out_md), "-o", str(out_docx),
        "--from", "markdown+pipe_tables+fenced_code_blocks+backtick_code_blocks+definition_lists",
        "--to", "docx", "--highlight-style", "tango", "--toc", "--toc-depth=2",
        "--number-sections", "-V", f"lang={args.locale}", "--standalone",
    ]
    if ref_docx.exists():
        cmd += ["--reference-doc", str(ref_docx)]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        size_mb = out_docx.stat().st_size / (1024 * 1024)
        print(f"\n[SUCCESS] DOCX generated: {out_docx}")
        print(f"          Size: {size_mb:.2f} MB")
    else:
        print("\n[ERROR] Pandoc failed:")
        print(result.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
