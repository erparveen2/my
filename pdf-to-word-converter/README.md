# PDF to Word Converter WordPress Plugin

This plugin adds a tool under **Tools > PDF to Word** that allows administrators to upload a PDF file and convert it to a Word (DOCX) document. Conversion is performed by calling `libreoffice` via the command line. Ensure `libreoffice` is installed on your server and accessible via PHP's `shell_exec`.

## Installation
1. Copy the `pdf-to-word-converter` folder to your WordPress `wp-content/plugins/` directory.
2. Activate the plugin from the WordPress admin Plugins page.
3. Navigate to **Tools > PDF to Word** to convert a PDF file.
