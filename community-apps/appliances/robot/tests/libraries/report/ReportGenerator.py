from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
import jinja2
import json
import markdown2
import pdfkit
import os


TEMPLATES_DIR = "/opt/robot-tests/tests/libraries/report/templates/"
CSS_FILENAME = TEMPLATES_DIR + "style.css"


class ReportGenerator:
    def generate_cover(self, title, date):
        cover = canvas.Canvas(
            "/opt/robot-tests/results/cover.pdf", pagesize=A4)
        pdfmetrics.registerFont(TTFont(
            'Georgia', '/opt/robot-tests/tests/libraries/report/fonts/georgia/georgia.ttf'))
        cover.setFont("Georgia", 30)

        # A4 = 595x891
        PAGE_WIDTH = A4[0]
        PAGE_HEIGHT = A4[1]

        # Draw the title
        cover.drawString(100, 750, "Functional and Performance Report")

        if title is not None:
            cover.setFont("Georgia", 20)
            cover.drawString(100, 700, "%s" % (title))
        if date is not None:
            cover.setFont("Georgia", 20)
            cover.drawString(100, 670, "Date: %s" % (date))
        cover.setFillColorRGB(0.0, 0.478, 0.745, 1)
        cover.rect(30, 20, 40, 800, 0, 1)
        cover.drawImage("/opt/robot-tests/tests/libraries/report/opennebula.png",
                        160, 350, 0.5*PAGE_WIDTH, preserveAspectRatio=True)
        cover.save()

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
                             css_file=CSS_FILENAME)

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

    def markdown_to_pdf(self, input_file, output_file, css_file=None):
        with open(input_file, 'r') as f:
            markdown_text = f.read()
        extras = ["tables", "fenced-code-blocks", "strike", "task_list", "toc", "code-friendly"]

        html = markdown2.markdown(markdown_text, extras=extras)

        if css_file:
            with open(css_file, 'r') as f:
                css_content = f.read()
            html = f"<style>{css_content}</style>\n" + html

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
            "dpi": "300"
        }

        pdfkit.from_string(html, output_file, options=options)
