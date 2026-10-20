"""One-time asset preparation, not an app/runtime dependency.

Source: Google Fonts ofl/manrope/Manrope[wght].ttf (SIL OFL, alongside assets).
The source defaults to weight 200; explicit static instances keep Flutter Web
typography consistent. Run with fonttools 4.67.0 installed.
"""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

font_dir = Path(__file__).resolve().parents[1] / 'assets' / 'fonts'
for weight in (400, 500, 600, 700):
    instance = instantiateVariableFont(
        TTFont(font_dir / 'Manrope.ttf'), {'wght': weight}, updateFontNames=True
    )
    instance.save(font_dir / f'Manrope-{weight}.ttf')
    print(f'Generated Manrope weight {weight}')
