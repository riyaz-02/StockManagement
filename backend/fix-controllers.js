const fs = require('fs');
const path = require('path');

const controllersDir = './controllers';
const files = fs.readdirSync(controllersDir).filter(f => f.endsWith('Controller.js'));

files.forEach(file => {
    const filePath = path.join(controllersDir, file);
    let content = fs.readFileSync(filePath, 'utf8');

    // Remove module.exports block at the end
    content = content.replace(/\r?\nmodule\.exports = \{[\s\S]*?\};?\s*$/m, '');

    fs.writeFileSync(filePath, content);
    console.log(`Fixed ${file}`);
});

console.log('Done!');
