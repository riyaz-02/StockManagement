const itemController = require('./controllers/itemController');

console.log('Exported functions:');
console.log(Object.keys(itemController));
console.log('\ncreatItem type:', typeof itemController.createItem);
