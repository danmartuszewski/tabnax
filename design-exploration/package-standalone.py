"""Bundle the local gallery for opening directly in a browser without a server."""
from pathlib import Path

root = Path(__file__).resolve().parent
html = (root / "index.html").read_text()
for name in ("styles", "lattice", "fold", "relay"):
    html = html.replace(
        f'<link rel="stylesheet" href="{name}.css">',
        "<style>\n" + (root / f"{name}.css").read_text() + "\n</style>",
    )
for name in ("lattice", "fold", "relay", "app"):
    html = html.replace(
        f'<script src="{name}.js"></script>',
        "<script>\n" + (root / f"{name}.js").read_text() + "\n</script>",
    )
(root / "tabnax-gallery.html").write_text(html)
print("Created tabnax-gallery.html; all styles and interaction code are embedded.")
