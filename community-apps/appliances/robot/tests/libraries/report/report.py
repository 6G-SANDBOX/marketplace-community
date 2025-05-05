from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont


def generate_cover(title, date):

    cover = canvas.Canvas("/opt/robot-tests/results/cover.pdf", pagesize=A4)
    pdfmetrics.registerFont(TTFont('Georgia', '/opt/robot-tests/tests/libraries/report/fonts/georgia/georgia.ttf'))
    cover.setFont("Georgia", 30)

    # A4 = 595x891
    PAGE_WIDTH  = A4[0]
    PAGE_HEIGHT = A4[1]

    # Draw the title
    cover.drawString(100, 750, "Functional and Performance Report")

    if title is not None:
        cover.setFont("Georgia", 20)
        cover.drawString(100, 700, "%s" %(title))
    if date is not None:
        cover.setFont("Georgia", 20)
        cover.drawString(100, 670, "Date: %s" %(date))
    cover.setFillColorRGB(0.0, 0.478, 0.745, 1)
    cover.rect(30, 20, 40, 800, 0, 1)
    cover.drawImage("/opt/robot-tests/tests/libraries/report/opennebula.png", 160, 350, 0.5*PAGE_WIDTH, preserveAspectRatio=True)
    cover.save()
