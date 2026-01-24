const puppeteer = require('puppeteer');
const fs = require('fs').promises;
const path = require('path');
const bwipjs = require('bwip-js');

class PDFGenerator {
    /**
     * Generate PDF for barcode tags
     * @param {Array} items - Array of item objects
     * @returns {Promise<Buffer>} PDF buffer
     */
    static async generateTagsPDF(items) {
        let browser;

        try {
            // Generate barcodes as data URLs first
            console.log('[PDF] Generating barcodes...');
            const itemsWithBarcodes = await Promise.all(
                items.map(async (item) => {
                    try {
                        const png = await bwipjs.toBuffer({
                            bcid: 'code128',
                            text: item.barcode,
                            scale: 2,
                            height: 7,
                            includetext: false,
                        });
                        return {
                            ...item,
                            barcodeDataUrl: `data:image/png;base64,${png.toString('base64')}`
                        };
                    } catch (err) {
                        console.error(`Error generating barcode for ${item.barcode}:`, err);
                        return { ...item, barcodeDataUrl: null };
                    }
                })
            );
            console.log(`[PDF] Generated ${itemsWithBarcodes.filter(i => i.barcodeDataUrl).length} barcodes`);

            // Read HTML template
            const templatePath = path.join(__dirname, '../templates/tag-template.html');
            let htmlTemplate = await fs.readFile(templatePath, 'utf-8');

            // Generate tags HTML with barcode data URLs
            const tagsHTML = this._generateTagsHTML(itemsWithBarcodes);

            // Replace placeholder
            const finalHTML = htmlTemplate.replace('{{TAGS_CONTENT}}', tagsHTML);

            // Launch browser
            browser = await puppeteer.launch({
                headless: 'new',
                args: [
                    '--no-sandbox',
                    '--disable-setuid-sandbox',
                    '--disable-dev-shm-usage',
                    '--disable-gpu'
                ]
            });

            const page = await browser.newPage();

            // Set content and wait for it to load
            await page.setContent(finalHTML, {
                waitUntil: ['networkidle0', 'domcontentloaded']
            });

            console.log('[PDF] HTML content loaded, generating PDF...');

            // Generate PDF
            const pdfBuffer = await page.pdf({
                format: 'A4',
                printBackground: true,
                preferCSSPageSize: false,
                margin: {
                    top: '0.5in',
                    right: '0.5in',
                    bottom: '0.5in',
                    left: '0.5in'
                }
            });

            console.log(`PDF generated successfully: ${pdfBuffer.length} bytes`);
            return pdfBuffer;

        } catch (error) {
            console.error('Error generating PDF:', error);
            throw new Error(`PDF generation failed: ${error.message}`);
        } finally {
            if (browser) {
                await browser.close();
            }
        }
    }

    /**
     * Generate HTML for all tags
     * @private
     */
    static _generateTagsHTML(items) {
        const tagsPerPage = 100; // 10 columns × 10 rows
        const pages = [];

        for (let i = 0; i < items.length; i += tagsPerPage) {
            const pageItems = items.slice(i, i + tagsPerPage);
            const pageTags = pageItems.map(item => this._generateSingleTag(item)).join('\n');

            // Fill remaining slots with empty tags
            const emptySlots = tagsPerPage - pageItems.length;
            const emptyTags = '<div class="tag"></div>'.repeat(emptySlots);

            pages.push(`<div class="page">${pageTags}${emptyTags}</div>`);
        }

        return pages.join('\n');
    }

    /**
     * Generate HTML for a single tag
     * @private
     */
    static _generateSingleTag(item) {
        const hasHallmark = item.huid && item.huid.trim() !== '';
        const colorClass = hasHallmark ? 'hallmark' : 'non-hallmark';

        return `
      <div class="tag">
        <!-- Front Side -->
        <div class="tag-front ${colorClass}">
          <div class="barcode-container">
            ${item.barcodeDataUrl ?
                `<img src="${item.barcodeDataUrl}" alt="${item.barcode}" style="width: 100%; height: 12px;" />` :
                `<div style="height: 12px; background: #f0f0f0;"></div>`
            }
            <div class="barcode-text">${item.barcode}</div>
          </div>
          <div class="purity-badge ${colorClass}">
            <span class="purity-text">${item.netWeight.toFixed(3)}g • ${item.purity}</span>
          </div>
        </div>
        
        <!-- Back Side -->
        <div class="tag-back ${colorClass}">
          <div class="item-name">${this._escapeHTML(item.name)}</div>
          <div class="weight-box ${colorClass}">
            <span class="weight-value">${item.netWeight.toFixed(3)}g</span>
          </div>
          ${hasHallmark ? `<div class="huid-badge ${colorClass}"><span class="huid-text">HUID: ${item.huid}</span></div>` : ''}
        </div>
      </div>
    `;
    }

    /**
     * Escape HTML special characters
     * @private
     */
    static _escapeHTML(text) {
        const map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        };
        return text.replace(/[&<>"']/g, m => map[m]);
    }
}

module.exports = PDFGenerator;
