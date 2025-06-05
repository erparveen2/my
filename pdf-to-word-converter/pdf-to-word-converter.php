<?php
/*
Plugin Name: PDF to Word Converter
Description: Convert PDF files to Word (DOCX) format.
Version: 1.0.0
Author: Codex Bot
*/

if (!defined('ABSPATH')) {
    exit; // Exit if accessed directly.
}

class PDF_to_Word_Converter {
    public function __construct() {
        add_action('admin_menu', array($this, 'register_menu'));
        add_action('admin_post_pdf_to_word_convert', array($this, 'handle_conversion'));
    }

    public function register_menu() {
        add_management_page('PDF to Word', 'PDF to Word', 'manage_options', 'pdf-to-word', array($this, 'render_page'));
    }

    public function render_page() {
        ?>
        <div class="wrap">
            <h1>PDF to Word Converter</h1>
            <form method="post" action="<?php echo admin_url('admin-post.php'); ?>" enctype="multipart/form-data">
                <input type="hidden" name="action" value="pdf_to_word_convert">
                <?php wp_nonce_field('pdf_to_word_convert'); ?>
                <input type="file" name="pdf_file" accept="application/pdf" required>
                <?php submit_button('Convert'); ?>
            </form>
        </div>
        <?php
    }

    public function handle_conversion() {
        if (!current_user_can('manage_options') || !check_admin_referer('pdf_to_word_convert')) {
            wp_die('Unauthorized request');
        }

        if (empty($_FILES['pdf_file']['tmp_name'])) {
            wp_die('No file uploaded.');
        }

        $uploaded = wp_handle_upload($_FILES['pdf_file'], array('test_form' => false));
        if (isset($uploaded['error'])) {
            wp_die('Upload error: ' . $uploaded['error']);
        }

        $pdf_file = $uploaded['file'];
        $output_dir = wp_get_upload_dir()['path'];
        $command = sprintf('libreoffice --headless --convert-to docx %s --outdir %s', escapeshellarg($pdf_file), escapeshellarg($output_dir));
        $result = shell_exec($command . ' 2>&1');

        $converted_file = str_replace('.pdf', '.docx', basename($pdf_file));
        $converted_path = trailingslashit($output_dir) . $converted_file;

        if (!file_exists($converted_path)) {
            wp_die('Conversion failed. Command output: ' . esc_html($result));
        }

        $download_url = trailingslashit(wp_get_upload_dir()['url']) . $converted_file;
        wp_redirect(add_query_arg('pdf_to_word_file', urlencode($download_url), admin_url('tools.php?page=pdf-to-word')));
        exit;
    }
}

new PDF_to_Word_Converter();

add_action('admin_notices', function() {
    if (!empty($_GET['pdf_to_word_file'])) {
        $file = esc_url_raw($_GET['pdf_to_word_file']);
        echo '<div class="notice notice-success"><p>Conversion complete. <a href="' . esc_url($file) . '">Download Word file</a></p></div>';
    }
});

?>
