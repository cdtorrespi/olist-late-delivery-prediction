"""Shared chart style: restrained palette, faint grid, thin marks."""

import matplotlib.pyplot as plt

BLUE = "#2a78d6"     # main series
ORANGE = "#eb6834"   # delays / alert
AQUA = "#1baf7a"     # comparison
GRAY = "#a3a29d"     # reference
INK = "#0b0b0b"
INK_2 = "#52514e"
SURFACE = "#fcfcfb"


def apply_style() -> None:
    plt.rcParams.update({
        "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE,
        "savefig.facecolor": SURFACE,
        "axes.edgecolor": "#d6d5d0",
        "axes.labelcolor": INK_2,
        "axes.titlecolor": INK,
        "axes.titleweight": "bold",
        "axes.titlesize": 12,
        "axes.titlelocation": "left",
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "axes.axisbelow": True,
        "axes.grid.axis": "y",
        "grid.color": "#e8e7e3",
        "grid.linewidth": 0.8,
        "xtick.color": INK_2,
        "ytick.color": INK_2,
        "font.size": 10,
        "lines.linewidth": 2,
        "legend.frameon": False,
        "figure.dpi": 110,
    })
