#!/usr/bin/env python3

import html
import re
import sys


def render_inline(text: str) -> str:
    escaped = html.escape(text)
    return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)


def main() -> None:
    list_open = False

    for raw_line in sys.stdin:
        line = raw_line.strip()

        if not line:
            if list_open:
                print("</ul>")
                list_open = False
            continue

        if line.startswith("# "):
            if list_open:
                print("</ul>")
                list_open = False
            print(f"<h1>{render_inline(line[2:])}</h1>")
            continue

        if line.startswith("## "):
            if list_open:
                print("</ul>")
                list_open = False
            print(f"<h2>{render_inline(line[3:])}</h2>")
            continue

        if line.startswith("### "):
            if list_open:
                print("</ul>")
                list_open = False
            print(f"<h3>{render_inline(line[4:])}</h3>")
            continue

        if line.startswith("- "):
            if not list_open:
                print("<ul>")
                list_open = True
            print(f"<li>{render_inline(line[2:])}</li>")
            continue

        if list_open:
            print("</ul>")
            list_open = False
        print(f"<p>{render_inline(line)}</p>")

    if list_open:
        print("</ul>")


if __name__ == "__main__":
    main()
