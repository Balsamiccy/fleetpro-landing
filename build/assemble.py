#!/usr/bin/env python3
"""
Static site assembler for Car Collector Studio marketing pages.

The site has no framework/build step (plain static HTML on Vercel), but
maintaining nav/footer/auth-modal markup by hand across a dozen pages is
error-prone. This script is the single source of truth: edit partials/
nav.html or footer.html once, re-run, and every page picks up the change.

Usage: python3 assemble.py
Reads:  build/pages/*.html   (page templates with {{NAV}} {{FOOTER}} {{AUTHMODAL}})
Writes: landing/<same relative path>
"""
import os
import re

BUILD_DIR = os.path.dirname(os.path.abspath(__file__))
PARTIALS_DIR = os.path.join(BUILD_DIR, "partials")
PAGES_DIR = os.path.join(BUILD_DIR, "pages")
OUT_DIR = os.path.normpath(os.path.join(BUILD_DIR, "..", "landing"))

def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

def main():
    nav = read(os.path.join(PARTIALS_DIR, "nav.html"))
    footer = read(os.path.join(PARTIALS_DIR, "footer.html"))
    auth = read(os.path.join(PARTIALS_DIR, "auth-modal.html"))

    count = 0
    for root, _dirs, files in os.walk(PAGES_DIR):
        for fname in files:
            if not fname.endswith(".html"):
                continue
            src_path = os.path.join(root, fname)
            rel = os.path.relpath(src_path, PAGES_DIR)
            page = read(src_path)

            missing = []
            if "{{NAV}}" not in page: missing.append("NAV")
            if "{{FOOTER}}" not in page: missing.append("FOOTER")
            if "{{AUTHMODAL}}" not in page: missing.append("AUTHMODAL")
            if missing:
                print(f"WARNING: {rel} missing placeholders: {missing}")

            page = page.replace("{{NAV}}", nav)
            page = page.replace("{{FOOTER}}", footer)
            page = page.replace("{{AUTHMODAL}}", auth)

            out_path = os.path.join(OUT_DIR, rel)
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, "w", encoding="utf-8") as f:
                f.write(page)
            count += 1
            print(f"built {rel}")
    print(f"\n{count} pages assembled -> {OUT_DIR}")

if __name__ == "__main__":
    main()
