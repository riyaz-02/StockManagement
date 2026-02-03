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
            // Fetch tag settings for purity colors
            console.log('[PDF] Fetching tag settings...');
            const Settings = require('../models/Settings');
            let purityColorMap = {};

            try {
                const tagSettings = await Settings.findOne({ category: 'tag', type: 'printing' });
                if (tagSettings && tagSettings.tagSettings && tagSettings.tagSettings.purityColors) {
                    tagSettings.tagSettings.purityColors.forEach(pc => {
                        purityColorMap[pc.purity] = pc.color;
                    });
                    console.log(`[PDF] Loaded ${Object.keys(purityColorMap).length} purity colors from settings`);
                } else {
                    console.log('[PDF] No tag settings found, using default colors');
                }
            } catch (err) {
                console.error('[PDF] Error loading tag settings:', err);
            }

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

            // Generate tags HTML with barcode data URLs and purity colors
            const tagsHTML = this._generateTagsHTML(itemsWithBarcodes, purityColorMap);

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
    static _generateTagsHTML(items, purityColorMap = {}) {
        const tagsPerPage = 100; // 10 columns × 10 rows
        const pages = [];

        for (let i = 0; i < items.length; i += tagsPerPage) {
            const pageItems = items.slice(i, i + tagsPerPage);
            const pageTags = pageItems.map(item => this._generateSingleTag(item, purityColorMap)).join('\n');

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
    static _generateSingleTag(item, purityColorMap = {}) {
        // Check certification type
        const isHallmarked = item.certificationType === 'hallmarked';
        const isHUID = item.certificationType === 'huid';
        const hasHUID = isHUID && item.huidNumber && item.huidNumber.trim() !== '';
        const colorClass = (isHallmarked || isHUID) ? 'hallmark' : 'non-hallmark';

        // Get purity color from settings or use default
        const purityColor = purityColorMap[item.purity] || '#FFD700';
        const purityStyle = `background-color: ${purityColor};`;

        // Dynamic font sizing for weight based on text length
        const weightText = `${item.netWeight.toFixed(3)}g`;
        const weightLength = weightText.length;
        let backWeightFontSize = '11pt'; // Default for back side
        let frontWeightFontSize = '10pt'; // Default for front side

        if (weightLength >= 10) {
            backWeightFontSize = '7pt'; // Very large weights (1000+)
            frontWeightFontSize = '6pt';
        } else if (weightLength >= 9) {
            backWeightFontSize = '8pt'; // Large weights (100-999)
            frontWeightFontSize = '7pt';
        } else if (weightLength >= 8) {
            backWeightFontSize = '9pt'; // Medium-large weights
            frontWeightFontSize = '8pt';
        } else if (weightLength >= 7) {
            backWeightFontSize = '10pt'; // Medium weights
            frontWeightFontSize = '9pt';
        }

        return `
      <div class="tag">
        <!-- Front Side -->
        <div class="tag-front ${colorClass}" style="${purityStyle}">
          <div class="barcode-container">
            ${item.barcodeDataUrl ?
                `<img src="${item.barcodeDataUrl}" alt="${item.barcode}" style="width: 100%; height: 12px;" />` :
                `<div style="height: 12px; background: #f0f0f0;"></div>`
            }
            <div class="barcode-text">${item.barcode}</div>
          </div>
          <div class="front-weight-display">
            <span class="front-weight-text" style="font-size: ${frontWeightFontSize};">${weightText}</span>
          </div>
        </div>
        
        <!-- Back Side -->
        <div class="tag-back ${colorClass}" style="${purityStyle}">
          <div class="item-name">${this._escapeHTML(item.name)}</div>
          <div class="weight-box ${colorClass}">
            <span class="weight-value" style="font-size: ${backWeightFontSize};">${weightText}</span>
          </div>
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
