from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.units import cm
import jinja2
import json
import markdown2
import pdfkit
import os
from pypdf import PdfReader, PdfWriter

# Constants for the report generation
TEMPLATES_DIR = "/opt/robot-tests/tests/libraries/report/templates/"
CSS_FILENAME = TEMPLATES_DIR + "style.css"
# The cover image for the report
COVER_IMAGE = "/opt/robot-tests/tests/libraries/report/opennebula.png"
# The font file for Georgia
FONT_FILENAME = "/opt/robot-tests/tests/libraries/report/fonts/georgia/georgia.ttf"
FONT_NAME = "Georgia"
# The watermark image for the report
WATERMARK_IMAGE = "/opt/robot-tests/tests/libraries/report/opennebula-25.png"


class ReportGenerator:
    def generate_cover(self, title, date, output_file):
        cover = canvas.Canvas(
            output_file, pagesize=A4)
        pdfmetrics.registerFont(TTFont(
            FONT_NAME, FONT_FILENAME))
        cover.setFont(FONT_NAME, 30)

        # A4 = 595x891
        PAGE_WIDTH = A4[0]
        PAGE_HEIGHT = A4[1]

        # Draw the title
        cover.drawString(100, 750, "Functional and Performance Report")

        if title is not None:
            cover.setFont(FONT_NAME, 20)
            cover.drawString(100, 700, "%s" % (title))
        if date is not None:
            cover.setFont(FONT_NAME, 20)
            cover.drawString(100, 670, "Date: %s" % (date))
        cover.setFillColorRGB(0.0, 0.478, 0.745, 1)
        cover.rect(30, 20, 40, 800, 0, 1)
        cover.drawImage(COVER_IMAGE,
                        160, 350, 0.5*PAGE_WIDTH, preserveAspectRatio=True)
        cover.save()

    def create_watermark(self, output_file, image_path=WATERMARK_IMAGE):
        print("Creating watermark at:", output_file)
        c = canvas.Canvas(output_file, pagesize=A4)
        width, height = A4
        print("Page size:", width, height)
        # Position and opacity settings
        c.saveState()
        c.translate(width / 2.0, height / 2.0)
        c.rotate(0)
        c.drawImage(image_path, -3*cm, -1*cm, width=6*cm, height=3*cm, mask='auto')
        c.restoreState()
        c.save()

    def apply_watermark(self, input_pdf, watermark_pdf):
        watermark = PdfReader(watermark_pdf).pages[0]

        files = []
        if isinstance(input_pdf, str):
            print("processing single input file:", input_pdf)
            files.append(input_pdf)
        if isinstance(input_pdf, list):
            print("processing multiple input files:", input_pdf)
            files = input_pdf

        for file in files:
            print("Processing file:", file)
            output_pdf = file
            reader = PdfReader(file)
            writer = PdfWriter()

            for page in reader.pages:
                page.merge_page(watermark)
                writer.add_page(page)

            with open(output_pdf, 'wb') as f:
                writer.write(f)

    def render(self, template, json_data):
        return jinja2.Environment(
            loader=jinja2.FileSystemLoader(TEMPLATES_DIR)
        ).get_template(template).render(json_data)

    def generate_report_page_pdf(self, template,
                                 json_filename,
                                 output_filename_pdf,
                                 optional_arguments={}):

        directory = os.path.dirname(output_filename_pdf)
        filename_with_ext = os.path.basename(output_filename_pdf)
        filename_without_ext = os.path.splitext(filename_with_ext)[0]

        print("Directory:", directory)
        print("File with extension:", filename_with_ext)
        print("File without extension:", filename_without_ext)

        output_filename_md = directory + "/" + filename_without_ext + ".md"

        self.generate_report_page(template,
                                  json_filename,
                                  output_filename_md,
                                  optional_arguments)

        # Generate the PDF file
        self.markdown_to_pdf(output_filename_md, output_filename_pdf,
                             css_file=CSS_FILENAME, image_file=None)

    def generate_report_page(self, template,
                             json_filename,
                             output_filename,
                             optional_arguments={}):
        # load json from file
        with open(json_filename) as json_file:
            json_data = json.load(json_file)

        json_data.update(optional_arguments)

        # Apply the template
        result = self.render(template, json_data)

        # write output to a file
        outFile = open(output_filename, "w")
        outFile.write(result)
        outFile.close()

    def markdown_to_pdf(self, input_file, output_file, css_file=None, image_file=None):
        with open(input_file, 'r') as f:
            markdown_text = f.read()
        extras = ["tables", "fenced-code-blocks",
                  "strike", "task_list", "toc", "code-friendly"]

        html = markdown2.markdown(markdown_text, extras=extras)

        watermark_div = ''
        if image_file:
            abs_img_path = os.path.abspath(image_file).replace('\\', '/')
            watermark_div = f'<div class="watermark"><img src="file://{abs_img_path}"/></div>'

        css_content = ''
        if css_file:
            with open(css_file, 'r') as f:
                css_content = f.read()

        html = f"""
        <html>
        <head>
            <style>{css_content}</style>
        </head>
        <body>
            {watermark_div}
            {html}
        </body>
        </html>
        """

        options = {
            "page-size": "A4",
            "margin-top": "10mm",
            "margin-right": "10mm",
            "margin-bottom": "10mm",
            "margin-left": "10mm",
            "encoding": "UTF-8",
            "quiet": "",
            "print-media-type": "",
            "zoom": "4",
            "dpi": "300",
            "enable-local-file-access": None
        }

        pdfkit.from_string(html, output_file, options=options)

    def join_pdfs(self, pdfs, output_pdf):
        writer = PdfWriter()

        for pdf_path in pdfs:
            reader = PdfReader(pdf_path)
            for page in reader.pages:
                writer.add_page(page)

        with open(output_pdf, "wb") as f:
            writer.write(f)
