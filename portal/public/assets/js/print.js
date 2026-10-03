// The print page: one button opens the browser's print dialog (also lets you save as PDF).
(function () {
    'use strict';
    document.addEventListener('click', function (e) {
        if (e.target.closest('[data-print]')) window.print();
    });
})();
