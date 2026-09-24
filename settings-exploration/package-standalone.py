from pathlib import Path
root = Path(__file__).resolve().parent
html = (root / 'index.html').read_text()
html = html.replace('<link rel="stylesheet" href="styles.css">', '<style>\n' + (root / 'styles.css').read_text() + '\n</style>')
for name in ('model.js', 'modes.js', 'app.js'):
    html = html.replace(f'<script src="{name}"></script>', '<script>\n' + (root / name).read_text() + '\n</script>')
(root / 'tabnax-settings.html').write_text(html)
print(root / 'tabnax-settings.html')
